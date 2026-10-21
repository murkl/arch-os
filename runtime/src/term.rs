//! The interface in the terminal it was started from.

use std::sync::mpsc::{self, RecvTimeoutError};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

use ratatui::crossterm::event::{
    self, DisableBracketedPaste, DisableMouseCapture, EnableBracketedPaste, EnableMouseCapture,
    Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseEventKind,
};

use crate::cli::Start;
use crate::ui::{App, FRAME, Key, Msg};

pub fn run(start: Start) -> std::io::Result<()> {
    let (tx, rx) = mpsc::channel();
    let keys = tx.clone();
    let gate = Arc::new(Gate::default());
    let pass = gate.clone();
    std::thread::spawn(move || {
        let mut last = None;
        loop {
            pass.pass();
            match event::poll(POLL) {
                Ok(true) => {}
                Ok(false) => continue,
                Err(_) => break,
            }
            let Ok(e) = event::read() else {
                break;
            };
            let msg = match e {
                Event::Key(k) if k.kind != KeyEventKind::Release => key(k).map(|key| {
                    let again = held(&mut last, key, Instant::now());
                    if again || k.kind == KeyEventKind::Repeat {
                        Msg::Held(key)
                    } else {
                        Msg::Key(key)
                    }
                }),
                Event::Mouse(m) => match m.kind {
                    MouseEventKind::ScrollUp => Some(Msg::Key(Key::WheelUp)),
                    MouseEventKind::ScrollDown => Some(Msg::Key(Key::WheelDown)),
                    _ => None,
                },
                Event::Resize(..) => Some(Msg::Resize),
                Event::Paste(text) => Some(Msg::Paste(text)),
                _ => None,
            };
            if let Some(msg) = msg
                && keys.send(msg).is_err()
            {
                break;
            }
        }
    });
    let mut app = App::new(
        start,
        &std::env::current_dir()?,
        tx,
        Arc::new(|| {}),
        console(),
    )?;
    let mut terminal = ratatui::init();
    mouse(true);
    let restore = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        mouse(false);
        restore(info);
    }));
    let result = (|| {
        let mut started = false;
        loop {
            terminal.draw(|f| app.draw(f))?;
            if !started {
                app.start();
                started = true;
            }
            let drawn = Instant::now();
            let wake = app.wake(drawn);
            match rx.recv_timeout(wake.saturating_duration_since(drawn)) {
                Ok(msg) => {
                    app.handle(msg);
                    // What follows within a frame is drawn with it, and a flood still gets drawn.
                    let (due, budget) = (drawn + FRAME, Instant::now() + FRAME);
                    while !app.done() && Instant::now() < budget {
                        match rx.recv_timeout(due.saturating_duration_since(Instant::now())) {
                            Ok(msg) => app.handle(msg),
                            Err(RecvTimeoutError::Timeout) => break,
                            Err(RecvTimeoutError::Disconnected) => return Ok(()),
                        }
                    }
                }
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => return Ok(()),
            }
            if !app.done() && Instant::now() >= wake {
                app.handle(Msg::Tick);
            }
            // A script given the terminal: the interface stands down for as long as it runs,
            // the key thread first. A read of the terminal from what is then a background
            // process group would stop this process, or spin on the error it gets instead.
            if let Some(job) = app.ctx.take_handover() {
                gate.pause();
                mouse(false);
                ratatui::restore();
                let result = job();
                terminal = ratatui::init();
                mouse(true);
                gate.resume();
                app.handle(Msg::Data(app.ctx.page_id(), result.into()));
            }
            if app.done() {
                return Ok(());
            }
        }
    })();
    mouse(false);
    ratatui::restore();
    result
}

/// How long the key thread waits for a key before it looks whether it is to stand still.
const POLL: Duration = Duration::from_millis(50);

/// Holds the key thread still while a script has the terminal. Pausing waits until the thread
/// stands, so no read of the terminal is under way once the script takes the foreground.
#[derive(Default)]
struct Gate {
    /// Whether a pause is wanted, and whether the thread stands.
    state: Mutex<(bool, bool)>,
    changed: Condvar,
}

impl Gate {
    /// Asks the key thread to stand still and waits until it does, or a moment for one that
    /// is gone.
    fn pause(&self) {
        let mut s = self.state.lock().unwrap_or_else(|e| e.into_inner());
        s.0 = true;
        let deadline = Instant::now() + Duration::from_secs(1);
        while !s.1 {
            let left = deadline.saturating_duration_since(Instant::now());
            if left.is_zero() {
                break;
            }
            s = self
                .changed
                .wait_timeout(s, left)
                .unwrap_or_else(|e| e.into_inner())
                .0;
        }
    }

    fn resume(&self) {
        let mut s = self.state.lock().unwrap_or_else(|e| e.into_inner());
        s.0 = false;
        self.changed.notify_all();
    }

    /// The key thread, before each look at the terminal: stands still for as long as it is
    /// asked to.
    fn pass(&self) {
        let mut s = self.state.lock().unwrap_or_else(|e| e.into_inner());
        if !s.0 {
            return;
        }
        s.1 = true;
        self.changed.notify_all();
        while s.0 {
            s = self.changed.wait(s).unwrap_or_else(|e| e.into_inner());
        }
        s.1 = false;
    }
}

/// The Linux console: TERM `linux`, or none or dumb, which promises nothing.
fn console() -> bool {
    match std::env::var("TERM").unwrap_or_default().as_str() {
        "" | "dumb" => true,
        term => term.starts_with("linux"),
    }
}

/// The wheel as scrolling: without it, a terminal sends the arrow keys instead. Pasted text
/// comes as one, not as keys.
fn mouse(capture: bool) {
    let mut out = std::io::stdout();
    let done = match capture {
        true => ratatui::crossterm::execute!(out, EnableMouseCapture, EnableBracketedPaste),
        false => ratatui::crossterm::execute!(out, DisableMouseCapture, DisableBracketedPaste),
    };
    if let Err(e) = done {
        crate::warn!("mouse capture {capture}: {e}");
    }
}

/// Faster than a hand presses a key twice, slower than a keyboard repeats it.
const REPEAT: Duration = Duration::from_millis(150);

/// Whether a key is held: a terminal sends its repeats as presses, so the same key again within
/// `REPEAT` of its last one counts as held.
fn held(last: &mut Option<(Key, Instant)>, key: Key, now: Instant) -> bool {
    let held = last.is_some_and(|(k, at)| k == key && now.duration_since(at) < REPEAT);
    *last = Some((key, now));
    held
}

fn key(k: KeyEvent) -> Option<Key> {
    let ctrl = k.modifiers.contains(KeyModifiers::CONTROL);
    Some(match k.code {
        KeyCode::Char(c) if ctrl => Key::Ctrl(c.to_ascii_lowercase()),
        KeyCode::Char(c) => Key::Char(c),
        KeyCode::Enter => Key::Enter,
        KeyCode::Esc => Key::Esc,
        KeyCode::Backspace => Key::Backspace,
        KeyCode::Delete => Key::Delete,
        KeyCode::Tab => Key::Tab,
        KeyCode::Up => Key::Up,
        KeyCode::Down => Key::Down,
        KeyCode::Left => Key::Left,
        KeyCode::Right => Key::Right,
        KeyCode::PageUp => Key::PageUp,
        KeyCode::PageDown => Key::PageDown,
        KeyCode::Home => Key::Home,
        KeyCode::End => Key::End,
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    /// Paused, the thread stands before the pause returns, and goes on once resumed.
    #[test]
    fn a_paused_gate_holds_the_thread_until_it_is_resumed() {
        let gate = Arc::new(Gate::default());
        let count = Arc::new(AtomicUsize::new(0));
        let (g, c) = (gate.clone(), count.clone());
        let thread = std::thread::spawn(move || {
            for _ in 0..300 {
                g.pass();
                c.fetch_add(1, Ordering::SeqCst);
                std::thread::sleep(Duration::from_millis(1));
            }
        });
        std::thread::sleep(Duration::from_millis(20));
        gate.pause();
        let stood = count.load(Ordering::SeqCst);
        std::thread::sleep(Duration::from_millis(50));
        assert_eq!(count.load(Ordering::SeqCst), stood, "moved while paused");
        gate.resume();
        std::thread::sleep(Duration::from_millis(50));
        assert!(count.load(Ordering::SeqCst) > stood, "never resumed");
        thread.join().unwrap();
    }

    #[test]
    fn a_key_coming_again_at_the_rate_of_a_keyboard_is_held() {
        let (mut last, start) = (None, Instant::now());
        let at = |ms| start + Duration::from_millis(ms);
        assert!(!held(&mut last, Key::Char('r'), at(0)));
        assert!(held(&mut last, Key::Char('r'), at(30)));
        assert!(!held(&mut last, Key::Char('j'), at(90)), "another key");
        assert!(!held(&mut last, Key::Char('j'), at(400)), "pressed again");
    }
}

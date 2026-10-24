//! Unattended run: answers from the answer file, passwords from environment variables of the
//! same name, every confirmation a yes, the log on stdout.

use std::sync::Arc;
use std::sync::mpsc::{self, Receiver, RecvTimeoutError};
use std::time::Duration;

use ratatui::Terminal;
use ratatui::backend::TestBackend;

use crate::cli::Start;
use crate::ui::{App, Msg};

/// Message timeout between checks of the current page.
const BEAT: Duration = Duration::from_millis(50);

/// Runs the module to its outcome and prints it. `false` on failure.
pub fn run(start: Start) -> std::io::Result<bool> {
    let (tx, rx) = mpsc::channel();
    let app = App::new(start, &std::env::current_dir()?, tx, Arc::new(|| {}), true)?;
    crate::log::echo(true);
    let terminal = Terminal::new(TestBackend::new(100, 40)).map_err(std::io::Error::other)?;
    Ok(match drive(app, terminal, rx) {
        Ok(words) => {
            println!("{words}");
            true
        }
        Err(why) => {
            crate::error!("{why}");
            false
        }
    })
}

/// Draws into an offscreen frame, since pages act when drawn, until the run has an outcome or a
/// page needs input.
fn drive(
    mut app: App,
    mut terminal: Terminal<TestBackend>,
    rx: Receiver<Msg>,
) -> Result<String, String> {
    terminal
        .draw(|f| app.draw(f))
        .map(drop)
        .map_err(|e| e.to_string())?;
    app.start();
    loop {
        match rx.recv_timeout(BEAT) {
            Ok(msg) => app.handle(msg),
            Err(RecvTimeoutError::Timeout) => app.handle(Msg::Tick),
            Err(RecvTimeoutError::Disconnected) => return Err("the interface stopped".into()),
        }
        terminal
            .draw(|f| app.draw(f))
            .map(drop)
            .map_err(|e| e.to_string())?;
        if let Some(outcome) = app.finished() {
            return outcome;
        }
        app.unattended()?;
        if app.done() {
            return Err("run ended without an outcome".into());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ui::app::tests::app;

    fn answered(app: &mut App) {
        for (name, value) in [
            ("TUX_KEYMAP", "us"),
            ("TUX_HOST", "tuxbox"),
            ("TUX_DESKTOP", "none"),
            ("TUX_DISK", "sda"),
        ] {
            app.ctx.store.set(name, value);
        }
        app.ctx.first = false;
    }

    /// The question a task asks is skipped, nothing answers it.
    #[test]
    fn runs_the_work_to_its_end_with_nobody_at_the_keyboard() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        crate::i18n::set("en");
        // SAFETY: every test that reads the environment holds the lock above.
        unsafe { std::env::set_var("TUX_PASSWORD", "pw") };
        let (mut app, terminal, rx) = app(false);
        answered(&mut app);
        let dir = app.ctx.store.path().parent().unwrap().to_path_buf();
        let outcome = drive(app, terminal, rx);
        unsafe { std::env::remove_var("TUX_PASSWORD") };
        let words = outcome.expect("finished");
        assert!(
            words.contains("tuxbox boots.") && words.contains("1 of 1 tests passed"),
            "{words}"
        );
        assert_eq!(
            std::fs::read_to_string(dir.join("host")).unwrap().trim(),
            "tuxbox"
        );
        assert_eq!(
            std::fs::read_to_string(dir.join("motd")).unwrap().trim(),
            "Welcome aboard",
            "a task's texts reach its script"
        );
    }

    #[test]
    fn stops_where_a_password_is_not_set() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        crate::i18n::set("en");
        unsafe { std::env::remove_var("TUX_PASSWORD") };
        let (mut app, terminal, rx) = app(false);
        answered(&mut app);
        let why = drive(app, terminal, rx).unwrap_err();
        assert!(why.contains("TUX_PASSWORD is not set"), "{why}");
    }
}

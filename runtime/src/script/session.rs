//! A background script: output to the log and the page, the fd 3 report for a failure.

use std::io::{BufRead, BufReader, Read};
use std::os::fd::{AsRawFd, BorrowedFd, FromRawFd, OwnedFd, RawFd};
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use rustix::io::Errno;
use rustix::process::{Pid, Signal, kill_process_group};

use unicode_width::UnicodeWidthStr;

use super::{Failure, Step};

#[derive(Debug)]
pub enum Event {
    /// A finished line.
    Line(String),
    /// The current state of a line redrawn in place.
    Drawn(String),
    Exit(Result<(), Failure>),
}

pub struct Session {
    pid: i32,
}

/// Stderr lines a failure keeps, since a tool's real message comes last.
const KEEP: usize = 8;
/// Time a stopped script gets to end by itself, so pacman finishes its package and arch-chroot
/// unmounts.
const GRACE: Duration = if cfg!(test) {
    Duration::from_millis(300)
} else {
    Duration::from_secs(10)
};
/// Time a killed process may take to exit. One in disk wait exits once the disk answers.
const GONE: Duration = Duration::from_secs(5);
const POLL: Duration = Duration::from_millis(50);

impl Session {
    pub(super) fn spawn(
        step: Step,
        mut cmd: Command,
        sink: impl Fn(Event) + Send + Sync + 'static,
    ) -> Result<Session, String> {
        let (events, events_w) =
            rustix::pipe::pipe_with(rustix::pipe::PipeFlags::CLOEXEC).map_err(|e| e.to_string())?;
        let raw = events_w.as_raw_fd();
        cmd.stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        // Own session: no terminal to stop on or draw into, and one group, so a stop reaches
        // everything the step started.
        // SAFETY: setsid, dup2 and fcntl are async-signal-safe.
        unsafe {
            cmd.pre_exec(move || {
                rustix::process::setsid()?;
                attach_fd3(raw)
            })
        };
        let mut child = cmd.spawn().map_err(|e| format!("bash: {e}"))?;
        drop(events_w);
        let pid = child.id() as i32;

        let sink = Arc::new(sink);
        let stderr_tail: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
        let out = child.stdout.take().unwrap();
        let err = child.stderr.take().unwrap();
        let readers = [
            follow(out, sink.clone(), None),
            follow(err, sink.clone(), Some(stderr_tail.clone())),
        ];
        // Read to the end: a read end closed early kills the script by SIGPIPE on its next
        // report.
        let fail = std::thread::spawn(move || {
            let mut first = None;
            for line in BufReader::new(std::fs::File::from(events))
                .lines()
                .map_while(Result::ok)
            {
                if first.is_none() && line.starts_with("fail\t") {
                    first = Some(line);
                }
            }
            first
        });
        std::thread::spawn(move || {
            let status = child.wait();
            // All lines arrive before the outcome.
            for r in readers {
                let _ = r.join();
            }
            let fail = fail.join().unwrap_or_default();
            let stderr = stderr_tail.lock().unwrap().join("\n");
            let result = match status {
                Ok(s) if s.success() => Ok(()),
                Ok(s) => Err(Failure::classify(
                    &step,
                    s.code().or(s.signal().map(|n| 128 + n)),
                    fail.as_deref(),
                    stderr,
                )),
                Err(e) => Err(Failure::new(&step, e.to_string())),
            };
            sink(Event::Exit(result));
        });
        Ok(Session { pid })
    }

    /// Stops the script and everything it started, returns once none of it runs. TERM first, so
    /// a package transaction ends between packages. KILL after the grace period, survivors are
    /// logged.
    pub fn stop(&self) {
        let Some(group) = Pid::from_raw(self.pid) else {
            return;
        };
        for (signal, bound) in [(Signal::TERM, GRACE), (Signal::KILL, GONE)] {
            match kill_process_group(group, signal) {
                Ok(()) => {}
                Err(Errno::SRCH) => return,
                Err(e) => {
                    crate::error!("stop: {}: {e}", self.pid);
                    return;
                }
            }
            let deadline = Instant::now() + bound;
            while Instant::now() < deadline {
                if running(self.pid).is_empty() {
                    return;
                }
                std::thread::sleep(POLL);
            }
        }
        crate::error!("stop: still running: {}", running(self.pid).join(", "));
    }
}

/// Live processes of a group as pid, name and state (D is disk wait). Zombies are left out, a
/// PID 1 may never reap them.
fn running(group: i32) -> Vec<String> {
    let Ok(dir) = std::fs::read_dir("/proc") else {
        return Vec::new();
    };
    let group = group.to_string();
    dir.filter_map(|e| std::fs::read_to_string(e.ok()?.path().join("stat")).ok())
        .filter_map(|stat| {
            // pid (name) state ppid pgrp …, where the name may hold spaces and parentheses.
            let (head, rest) = stat.rsplit_once(") ")?;
            let (pid, name) = head.split_once(" (")?;
            let mut fields = rest.split(' ');
            let state = fields.next()?;
            (state != "Z" && fields.nth(1)? == group).then(|| format!("{pid} {name} {state}"))
        })
        .collect()
}

/// Puts `fd` at 3 in the child, where the trap writes its report. Runs between fork and exec.
fn attach_fd3(fd: RawFd) -> std::io::Result<()> {
    // SAFETY: fd stays open in the parent until spawn returns, and 3 is ours to replace in the child.
    unsafe {
        let source = BorrowedFd::borrow_raw(fd);
        if fd == 3 {
            rustix::io::fcntl_setfd(source, rustix::io::FdFlags::empty())?;
        } else {
            let mut three = std::mem::ManuallyDrop::new(OwnedFd::from_raw_fd(3));
            rustix::io::dup2(source, &mut three)?;
        }
    }
    Ok(())
}

/// Reads a pipe to the end: finished lines to the log and the sink, a line redrawn in place to
/// the sink, and optionally the tail for the failure.
fn follow(
    mut r: impl Read + Send + 'static,
    sink: Arc<dyn Fn(Event) + Send + Sync>,
    tail: Option<Arc<Mutex<Vec<String>>>>,
) -> std::thread::JoinHandle<()> {
    std::thread::spawn(move || {
        let mut buf: Vec<u8> = Vec::new();
        let mut chunk = [0u8; 8192];
        loop {
            let n = match r.read(&mut chunk) {
                Ok(0) => break,
                Ok(n) => n,
                // A signal cut the read short, not the output.
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            };
            buf.extend_from_slice(&chunk[..n]);
            while let Some(i) = buf.iter().position(|&b| b == b'\n') {
                let line: Vec<u8> = buf.drain(..=i).collect();
                let line = drawn(&line[..line.len() - 1]);
                if line.is_empty() {
                    continue;
                }
                crate::log::write("OUT", &line);
                if let Some(tail) = &tail {
                    let mut tail = tail.lock().unwrap();
                    tail.push(line.clone());
                    if tail.len() > KEEP {
                        tail.remove(0);
                    }
                }
                sink(Event::Line(line));
            }
            // An unfinished line is a progress bar redrawing itself. Shown as is, only its end
            // kept.
            if buf.len() > 4096 {
                buf.drain(..buf.len() - 4096);
            }
            let current = drawn(&buf);
            if !current.is_empty() {
                sink(Event::Drawn(current));
            }
        }
        let rest = drawn(&buf);
        if !rest.is_empty() {
            crate::log::write("OUT", &rest);
            if let Some(tail) = &tail {
                tail.lock().unwrap().push(rest.clone());
            }
            sink(Event::Line(rest));
        }
    })
}

/// The last redraw after `\r`, without escapes and control characters, which would corrupt the
/// frame. Tabs expand to stops of eight, as in a terminal.
fn drawn(bytes: &[u8]) -> String {
    let text = String::from_utf8_lossy(bytes);
    let last = text
        .rsplit('\r')
        .find(|s| !s.trim().is_empty())
        .unwrap_or_default();
    let mut out = String::new();
    let mut chars = last.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '\x1b' => match chars.next() {
                Some('[') => {
                    for c in chars.by_ref() {
                        if ('\x40'..='\x7e').contains(&c) {
                            break;
                        }
                    }
                }
                Some(']') => {
                    while let Some(c) = chars.next() {
                        if c == '\x07' || (c == '\x1b' && chars.peek() == Some(&'\\')) {
                            chars.next_if_eq(&'\\');
                            break;
                        }
                    }
                }
                _ => {}
            },
            '\t' => out.extend(std::iter::repeat_n(' ', 8 - out.width() % 8)),
            c if c.is_control() => {}
            c => out.push(c),
        }
    }
    out.trim().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_color_and_keeps_the_last_redraw() {
        assert_eq!(
            drawn(b"\x1b[1;32m:: \x1b[0mSynchronizing"),
            ":: Synchronizing"
        );
        assert_eq!(drawn(b"( 1/2) 50%\r( 2/2) 100%"), "( 2/2) 100%");
        assert_eq!(drawn(b"( 1/2) 50%\r"), "( 1/2) 50%");
        assert_eq!(drawn(b"\x1b]0;title\x07done\tnow"), "done    now");
        assert_eq!(drawn(b"a\tb\tc"), "a       b       c");
        assert_eq!(
            drawn(b"one\r\r"),
            "one",
            "a line ended with \\r\\n by its program"
        );
    }
}

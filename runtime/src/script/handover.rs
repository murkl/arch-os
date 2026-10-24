//! Hands the terminal to a script, such as a shell in the new system, in its own foreground
//! process group. The terminal is reclaimed afterwards, since an interactive shell hands back a
//! group that is gone by then.

use std::os::fd::{AsFd, AsRawFd};
use std::os::unix::process::CommandExt;
use std::process::{Command, ExitStatus, Stdio};

/// The controlling terminal, wherever stdin, stdout and stderr point.
const TTY: &str = "/dev/tty";

pub fn run(mut cmd: Command) -> Result<ExitStatus, String> {
    let tty = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(TTY)
        .map_err(|e| format!("{}: {e}", crate::i18n::t("No terminal available.")))?;
    let clone = || tty.try_clone().map_err(|e| e.to_string());
    cmd.stdin(Stdio::from(clone()?))
        .stdout(Stdio::from(clone()?))
        .stderr(Stdio::from(clone()?));
    // Only a controlling terminal has a foreground to hand over.
    let Ok(own) = rustix::termios::tcgetpgrp(tty.as_fd()) else {
        return cmd.status().map_err(|e| e.to_string());
    };
    let fd = tty.as_raw_fd();
    // SAFETY: only async-signal-safe calls between fork and exec. SIGTTOU is ignored while the
    // child, still in the background, takes the foreground.
    unsafe {
        cmd.pre_exec(move || {
            rustix::process::setpgid(None, None)?;
            libc::signal(libc::SIGTTOU, libc::SIG_IGN);
            let me = rustix::process::getpid();
            rustix::termios::tcsetpgrp(std::os::fd::BorrowedFd::borrow_raw(fd), me)?;
            libc::signal(libc::SIGTTOU, libc::SIG_DFL);
            Ok(())
        });
    }
    let status = cmd.status().map_err(|e| e.to_string());
    // Reclaiming from what is now a background group raises SIGTTOU, so it is ignored for the
    // call.
    unsafe {
        libc::signal(libc::SIGTTOU, libc::SIG_IGN);
    }
    let reclaimed = rustix::termios::tcsetpgrp(tty.as_fd(), own);
    unsafe {
        libc::signal(libc::SIGTTOU, libc::SIG_DFL);
    }
    reclaimed.map_err(|e| format!("the terminal could not be taken back: {e}"))?;
    status
}

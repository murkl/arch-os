//! A script given the terminal outright, for as long as it runs: a shell in the new system. It
//! gets a foreground process group of its own, and this process takes the terminal back
//! afterwards, since an interactive shell hands back a group that is gone by then.

use std::os::fd::{AsFd, AsRawFd};
use std::os::unix::process::CommandExt;
use std::process::{Command, ExitStatus, Stdio};

/// The terminal this process was started on, whatever its three channels were pointed at.
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
    // Only a terminal this process controls has a foreground to hand over.
    let Ok(own) = rustix::termios::tcgetpgrp(tty.as_fd()) else {
        return cmd.status().map_err(|e| e.to_string());
    };
    let fd = tty.as_raw_fd();
    // SAFETY: only async-signal-safe calls between fork and exec. SIGTTOU is ignored for the
    // moment the child, still in the background, takes the foreground, and default again after.
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
    // Back to the foreground, asked from what is now a background group, which the kernel stops
    // for it unless the stop is ignored for the length of the call.
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

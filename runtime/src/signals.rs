//! SIGTERM, SIGHUP and SIGINT stop the work as leaving does. By default they end the program at
//! once, and a script in its own session runs on without it.

use std::io::Read;
use std::os::fd::IntoRawFd;
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::mpsc::Sender;

use crate::ui::Msg;

/// Write end of the pipe that wakes the reader.
static WAKE: AtomicI32 = AtomicI32::new(-1);

extern "C" fn caught(_: libc::c_int) {
    // SAFETY: write is async-signal-safe, and the pipe stays open while the program runs.
    unsafe { libc::write(WAKE.load(Ordering::Relaxed), [0u8].as_ptr().cast(), 1) };
}

/// Sends `Msg::Stop` for each of the three signals.
pub fn forward(tx: Sender<Msg>) -> std::io::Result<()> {
    let (read, write) = rustix::pipe::pipe_with(rustix::pipe::PipeFlags::CLOEXEC)?;
    WAKE.store(write.into_raw_fd(), Ordering::Relaxed);
    for signal in [libc::SIGTERM, libc::SIGHUP, libc::SIGINT] {
        // SAFETY: the handler only writes to a pipe. A child gets the default back at exec.
        unsafe { libc::signal(signal, caught as *const () as libc::sighandler_t) };
    }
    std::thread::spawn(move || {
        let mut read = std::fs::File::from(read);
        let mut byte = [0u8];
        loop {
            match read.read(&mut byte) {
                Ok(0) => return,
                Ok(_) => {
                    if tx.send(Msg::Stop).is_err() {
                        return;
                    }
                }
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                Err(_) => return,
            }
        }
    });
    Ok(())
}

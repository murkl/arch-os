//! One log per module run: runtime lines and script output, stamped in the time zone current at
//! each line.

use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};

static FILE: Mutex<Option<(File, PathBuf)>> = Mutex::new(None);

/// Copies each line to stdout for an unattended run.
static ECHO: AtomicBool = AtomicBool::new(false);

pub fn echo(on: bool) {
    ECHO.store(on, Ordering::Relaxed);
}

/// Opens `path` and keeps a log that holds a run as `.log.old`. One without a run is continued,
/// so starting the program again, as a kiosk does, keeps the last run's log. Until it succeeds
/// every write is a no-op, a missing log never stops a run.
pub fn init(path: &Path) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    if ran(path) {
        std::fs::rename(path, path.with_extension("log.old"))?;
    }
    let file = OpenOptions::new().create(true).append(true).open(path)?;
    *FILE.lock().unwrap() = Some((file, path.to_path_buf()));
    Ok(())
}

/// Whether the log holds a script's command or output, by the level after the 19 characters of
/// the time.
fn ran(path: &Path) -> bool {
    let Ok(file) = File::open(path) else {
        return false;
    };
    BufReader::new(file)
        .split(b'\n')
        .map_while(Result::ok)
        .any(|line| matches!(line.get(20..26), Some(b"RUN   " | b"OUT   ")))
}

pub fn path() -> Option<PathBuf> {
    FILE.lock().unwrap().as_ref().map(|(_, p)| p.clone())
}

pub fn write(level: &str, msg: &str) {
    let mut guard = FILE.lock().unwrap();
    let Some((file, _)) = guard.as_mut() else {
        return;
    };
    let now = now();
    let echo = ECHO.load(Ordering::Relaxed);
    for line in msg.lines() {
        let _ = writeln!(file, "{now} {level:<5} {line}");
        // A closed stdout must not end the run the log records.
        if echo {
            let _ = writeln!(std::io::stdout(), "{now} {level:<5} {line}");
        }
    }
}

/// Reads `/etc/localtime` per call, since a run may set the zone. `TZ` wins.
pub fn now() -> String {
    static ZONE: Mutex<Option<(String, jiff::tz::TimeZone)>> = Mutex::new(None);
    let tz = match std::env::var_os("TZ") {
        Some(_) => jiff::tz::TimeZone::system(),
        None => {
            let target = std::fs::read_link("/etc/localtime")
                .map(|p| p.display().to_string())
                .unwrap_or_default();
            let mut zone = ZONE.lock().unwrap();
            match zone.as_ref() {
                Some((linked, tz)) if *linked == target => tz.clone(),
                _ => {
                    let name = target
                        .rsplit_once("zoneinfo/")
                        .map(|(_, n)| n)
                        .unwrap_or_default();
                    let tz = jiff::tz::TimeZone::get(name).unwrap_or(jiff::tz::TimeZone::UTC);
                    *zone = Some((target, tz.clone()));
                    tz
                }
            }
        }
    };
    jiff::Timestamp::now()
        .to_zoned(tz)
        .strftime("%Y-%m-%d %H:%M:%S")
        .to_string()
}

#[macro_export]
macro_rules! info {
    ($($arg:tt)*) => { $crate::log::write("INFO", &format!($($arg)*)) };
}

#[macro_export]
macro_rules! warn {
    ($($arg:tt)*) => { $crate::log::write("WARN", &format!($($arg)*)) };
}

#[macro_export]
macro_rules! error {
    ($($arg:tt)*) => { $crate::log::write("ERROR", &format!($($arg)*)) };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_a_log_that_holds_a_run_is_set_aside() {
        let path = std::env::temp_dir().join(format!("rt-log-{}.log", std::process::id()));
        std::fs::write(&path, "2026-01-01 10:00:00 INFO  Installer 2.0.0\n").unwrap();
        assert!(!ran(&path));
        std::fs::write(
            &path,
            "2026-01-01 10:00:00 INFO  RUN   nothing\n2026-01-01 10:00:01 RUN   pacstrap\n",
        )
        .unwrap();
        assert!(ran(&path));
        std::fs::remove_file(&path).unwrap();
        assert!(!ran(&path));
    }
}

//! One log per module run: runtime lines and script output, stamped in the time zone current at
//! each line.

use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};

static FILE: Mutex<Option<(File, PathBuf)>> = Mutex::new(None);

/// Copies each line to stdout for an unattended run.
static ECHO: AtomicBool = AtomicBool::new(false);

pub fn echo(on: bool) {
    ECHO.store(on, Ordering::Relaxed);
}

/// Opens `path` and keeps the previous run as `.log.old`. Until it succeeds every write is a
/// no-op, a missing log never stops a run.
pub fn init(path: &Path) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    if path.exists() {
        std::fs::rename(path, path.with_extension("log.old"))?;
    }
    let file = OpenOptions::new().create(true).append(true).open(path)?;
    *FILE.lock().unwrap() = Some((file, path.to_path_buf()));
    Ok(())
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
        if echo {
            println!("{now} {level:<5} {line}");
        }
    }
}

/// Reads `/etc/localtime` per line, since a run may set the zone. `TZ` wins.
fn now() -> String {
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

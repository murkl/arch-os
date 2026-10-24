//! `--trace <file>`: page, focus and task changes as ids, one line each, for test harnesses that
//! must not read text off the screen.

use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::Path;

#[derive(Default)]
pub struct Trace(Option<File>);

impl Trace {
    pub fn open(path: &Path) -> std::io::Result<Trace> {
        let file = OpenOptions::new().create(true).append(true).open(path)?;
        Ok(Trace(Some(file)))
    }

    /// Unbuffered, since a harness polls the file while the program runs.
    pub fn line(&mut self, kind: &str, id: &str) {
        if let Some(file) = &mut self.0 {
            let _ = writeln!(file, "{kind} {id}");
        }
    }
}

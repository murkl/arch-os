//! The only place this program starts a process. Everything the runtime does is shell, handed
//! the answers as variables and read back as an exit status or stdout.
//!
//! The embedded product is written out once per process, readable by this user only, and every
//! script runs from there with lib.sh in front of it.

mod handover;
mod session;

pub use session::{Event, Session};

use std::os::unix::fs::DirBuilderExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::OnceLock;

use crate::i18n::t;
use crate::spec::{self, Shell};

static DIR: OnceLock<Result<PathBuf, String>> = OnceLock::new();

/// The product on disk: `$XDG_RUNTIME_DIR/<program>-<pid>`, or under the temp dir.
pub fn dir() -> Result<&'static Path, String> {
    DIR.get_or_init(|| {
        let base = std::env::var_os("XDG_RUNTIME_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir);
        let dir = base.join(format!("{}-{}", env!("CARGO_PKG_NAME"), std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::DirBuilder::new()
            .mode(0o700)
            .create(&dir)
            .map_err(|e| format!("{}: {e}", dir.display()))?;
        for (name, bytes) in crate::embedded::FILES {
            let path = dir.join(name);
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent)
                    .map_err(|e| format!("{}: {e}", parent.display()))?;
            }
            std::fs::write(&path, bytes).map_err(|e| format!("{name}: {e}"))?;
        }
        Ok(dir)
    })
    .as_ref()
    .map(PathBuf::as_path)
    .map_err(Clone::clone)
}

pub fn cleanup() {
    if let Some(Ok(dir)) = DIR.get() {
        let _ = std::fs::remove_dir_all(dir);
    }
}

/// A file of the product, where it lies now.
fn path(rel: &str) -> Result<PathBuf, String> {
    Ok(dir()?.join(rel))
}

/// The library every script gets in front of it, or nothing where the product has none.
fn lib() -> Result<String, String> {
    #[cfg(test)]
    if let Some(lib) = tests::LIB.get() {
        return Ok(lib.clone());
    }
    if !spec::loaded().lib {
        return Ok(String::new());
    }
    Ok(path(spec::LIB)?.display().to_string())
}

fn quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', r"'\''"))
}

/// Shell a declaration names, as one piece of shell.
fn piece(shell: &Shell) -> Result<String, String> {
    Ok(match shell {
        Shell::Call(name) => name.clone(),
        Shell::File(rel) => format!("source {}", quote(&path(rel)?.display().to_string())),
    })
}

/// A snippet: an option list, a suggestion. The library is sourced before anything else, so a
/// fault inside it is not blamed on the script about to run. No trap: a non-zero status is an
/// answer.
const SNIPPET: &str = "[ -z \"$2\" ] || source \"$2\" || exit $?\neval \"$1\"";

/// A question with a yes or no for an answer, wrapped in a function so `return 0` says yes.
const GUARD: &str =
    "[ -z \"$2\" ] || source \"$2\" || exit $?\neval \"rt_guard() {\n$1\n}\"\nrt_guard\nexit $?";

/// A script file, under the trap that reports on fd 3 where it broke: code, file, line, command.
/// `-e` stays off, since `source` hands back the status of a benign last line. A script that
/// stops itself with `exit` leaves no report, which is how a chosen status is told from a broken
/// command. The DEBUG trap remembers the script's own last line for one that hands back a
/// status without a failing command.
const FILE: &str = concat!(
    "set -Eo pipefail -T\n",
    "[ -z \"$2\" ] || source \"$2\" || exit $?\n",
    "trap 'c=$?; s=${BASH_SOURCE[0]}; [ -n \"$s\" ] && { printf \"fail\\t%d\\t%s\\t%d\\t%s\\n\" \"$c\" \"$s\" \"$LINENO\" \"$BASH_COMMAND\" >&3; exit $c; }' ERR\n",
    "trap '[ \"${BASH_SOURCE[0]}\" = \"$1\" ] && { rt_line=$LINENO; rt_cmd=$BASH_COMMAND; }; :' DEBUG\n",
    "source \"$1\"\n",
    "c=$?\n",
    "[ \"$c\" -eq 0 ] || printf \"fail\\t%d\\t%s\\t%d\\t%s\\n\" \"$c\" \"$1\" \"${rt_line:-0}\" \"$rt_cmd\" >&3\n",
    "exit $c"
);

/// bash with a wrapper, what it runs as `$1` and the library as `$2`, and the answers.
fn bash(wrapper: &str, payload: &str, env: &[(String, String)]) -> Result<Command, String> {
    let mut cmd = Command::new("bash");
    cmd.arg("-c")
        .arg(wrapper)
        .arg("--")
        .arg(payload)
        .arg(lib()?);
    cmd.envs(env.iter().map(|(k, v)| (k.as_str(), v.as_str())));
    Ok(cmd)
}

/// What a snippet said on the way out: the last lines of stderr, or its status.
fn said(out: &std::process::Output) -> String {
    let err = String::from_utf8_lossy(&out.stderr);
    let lines: Vec<&str> = err.lines().filter(|l| !l.trim().is_empty()).collect();
    if lines.is_empty() {
        return match out.status.code() {
            Some(c) => format!("exit {c}"),
            None => "stopped by a signal".into(),
        };
    }
    lines[lines.len().saturating_sub(8)..].join("\n")
}

/// Runs a snippet and returns what it printed, trimmed at the end.
pub fn run(shell: &Shell, env: &[(String, String)]) -> Result<String, String> {
    let out = bash(SNIPPET, &piece(shell)?, env)?
        .output()
        .map_err(|e| format!("bash: {e}"))?;
    if !out.status.success() {
        return Err(said(&out));
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim_end().to_string())
}

/// What a snippet printed, one entry per line, blank lines dropped. Only the end of a line is
/// trimmed: a leading tab follows an empty value, which is an answer too.
pub fn lines(shell: &Shell, env: &[(String, String)]) -> Result<Vec<String>, String> {
    Ok(run(shell, env)?
        .lines()
        .map(|l| l.trim_end().to_string())
        .filter(|l| !l.trim().is_empty())
        .collect())
}

/// Runs an action by itself, as a question with a yes or no for an answer. What it said on stderr
/// with a no is what somebody reads.
pub fn guard(script: &str, env: &[(String, String)]) -> Result<(), String> {
    let payload = format!("source {}", quote(&path(script)?.display().to_string()));
    let out = bash(GUARD, &payload, env)?
        .output()
        .map_err(|e| format!("bash: {e}"))?;
    if out.status.success() {
        return Ok(());
    }
    Err(said(&out))
}

/// One piece of a module's work as this layer takes it: the script, what a failure calls it,
/// and whether it is an action's rather than a task's.
#[derive(Clone, Debug)]
pub struct Step {
    pub module: String,
    pub name: String,
    pub action: bool,
    /// The script in the product.
    pub file: String,
}

/// Starts a step in the background, its output to the log and the events to `sink`.
pub fn start(
    step: Step,
    env: &[(String, String)],
    sink: impl Fn(Event) + Send + Sync + 'static,
) -> Result<Session, String> {
    let file = path(&step.file)?.display().to_string();
    let cmd = bash(FILE, &file, env)?;
    Session::spawn(step, cmd, sink)
}

/// Runs an action on the terminal itself, in place of the interface, and waits for it. Nothing
/// is captured or logged: its output is the terminal's.
pub fn handover(step: &Step, env: &[(String, String)]) -> Result<(), Box<Failure>> {
    let file = path(&step.file).map_err(|e| Box::new(Failure::new(step, e)))?;
    let payload = format!("source {}", quote(&file.display().to_string()));
    let cmd = bash(SNIPPET, &payload, env).map_err(|e| Box::new(Failure::new(step, e)))?;
    match handover::run(cmd) {
        Ok(status) if status.success() => Ok(()),
        Ok(status) => Err(Box::new(Failure {
            code: status.code().unwrap_or(1),
            script: step.file.clone(),
            ..Failure::new(step, String::new())
        })),
        Err(e) => Err(Box::new(Failure::new(step, e))),
    }
}

/// What a script reports back when it dies, in one shape: which module, which step, which file
/// and line, what ran and what it said on the way out.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Failure {
    pub module: String,
    pub unit: String,
    pub action: bool,
    pub script: String,
    pub line: u32,
    pub code: i32,
    pub command: String,
    pub stderr: String,
    /// The script stopped itself with `exit`: no command failed, so the status is one it chose
    /// and may have words for.
    pub deliberate: bool,
}

impl Failure {
    pub fn new(step: &Step, stderr: String) -> Failure {
        Failure {
            module: step.module.clone(),
            unit: step.name.clone(),
            action: step.action,
            code: 1,
            stderr,
            ..Failure::default()
        }
    }

    /// From the exit status, the first `fail` line the trap wrote, and what stderr said.
    pub fn classify(step: &Step, code: Option<i32>, fail: Option<&str>, stderr: String) -> Failure {
        let mut f = Failure::new(step, stderr);
        f.code = code.unwrap_or(1);
        match fail.map(|l| l.split('\t').collect::<Vec<_>>()) {
            Some(fields) if fields.len() >= 5 && fields[0] == "fail" => {
                f.code = fields[1].parse().unwrap_or(f.code);
                f.script = short(fields[2]);
                f.line = fields[3].parse().unwrap_or(0);
                f.command = fields[4].to_string();
            }
            _ => {
                f.script = step.file.clone();
                f.deliberate = code.is_some_and(|c| c > 0);
            }
        }
        f
    }

    /// The rows of a failure report, each a label and its value: short wins over exact.
    pub fn fields(&self) -> Vec<(String, String)> {
        let mut out = Vec::new();
        let mut add = |label: String, value: &str| {
            if !value.is_empty() {
                out.push((label, value.to_string()));
            }
        };
        add(t("Module"), &self.module);
        add(
            if self.action { t("Action") } else { t("Task") },
            &self.unit,
        );
        if !self.script.is_empty() {
            let where_ = if self.line > 0 {
                format!("{}:{}", self.script, self.line)
            } else {
                self.script.clone()
            };
            add(t("Script"), &where_);
        }
        add(t("Command"), &self.command);
        if self.code != 0 {
            add(t("Exit code"), &self.code.to_string());
        }
        out
    }
}

impl std::fmt::Display for Failure {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{} failed", self.unit)?;
        for (label, value) in self.fields() {
            write!(f, "\n{label:<11} {value}")?;
        }
        if !self.stderr.is_empty() {
            write!(f, "\n{:<11} {}", "Error", self.stderr)?;
        }
        Ok(())
    }
}

/// A script's path as whoever wrote it knows it: relative to the product.
fn short(p: &str) -> String {
    match dir() {
        Ok(dir) => Path::new(p)
            .strip_prefix(dir)
            .map(|r| r.display().to_string())
            .unwrap_or_else(|_| p.to_string()),
        Err(_) => p.to_string(),
    }
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use std::time::Duration;

    /// The library the tests' scripts get: the fixture's, once a test asked for it.
    pub static LIB: OnceLock<String> = OnceLock::new();

    /// Writes the fixture product where the real one lies, so its scripts run from there, and
    /// puts its library in front of every script.
    pub fn use_fixture() {
        let dir = dir().unwrap();
        for (rel, bytes) in crate::spec::tests::fixture() {
            let path = if rel == "lib.sh" {
                dir.join("fixture-lib.sh")
            } else {
                dir.join(rel)
            };
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(&path, bytes).unwrap();
        }
        let _ = LIB.set(dir.join("fixture-lib.sh").display().to_string());
    }

    /// A step of a fixture script, written where the real ones lie, with the fixture's library
    /// in front of it whatever product is embedded.
    pub fn step(body: &str) -> Step {
        use_fixture();
        let name = format!("t{}", rand());
        let rel = format!("fixture/{name}.sh");
        let file = dir().unwrap().join(&rel);
        std::fs::create_dir_all(file.parent().unwrap()).unwrap();
        std::fs::write(&file, body).unwrap();
        Step {
            module: "Fixture".into(),
            name: name.clone(),
            action: false,
            file: rel,
        }
    }

    fn rand() -> u128 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    }

    /// Runs a step to its end and returns the outcome and the lines it drew.
    pub fn drive(body: &str, env: &[(String, String)]) -> (Result<(), Failure>, Vec<String>) {
        let (tx, rx) = std::sync::mpsc::channel();
        let session = start(step(body), env, move |e| drop(tx.send(e))).unwrap();
        let mut lines = Vec::new();
        let deadline = std::time::Instant::now() + Duration::from_secs(10);
        while std::time::Instant::now() < deadline {
            match rx.recv_timeout(Duration::from_millis(50)) {
                Ok(Event::Line(l)) => lines.push(l),
                Ok(Event::Exit(r)) => return (r, lines),
                Err(_) => {}
            }
        }
        let _ = session;
        panic!("the script did not end");
    }

    #[test]
    fn a_failing_command_names_file_line_and_command() {
        let (r, _) = drive("echo one\nfalse\necho two\n", &[]);
        let f = r.unwrap_err();
        assert!(f.script.starts_with("fixture/"), "{f:?}");
        assert_eq!(
            (f.line, f.command.as_str(), f.code, f.deliberate),
            (2, "false", 1, false)
        );
    }

    #[test]
    fn exit_is_deliberate_and_a_failing_last_line_is_not() {
        let (r, _) = drive("echo x >&2\nexit 7\n", &[]);
        let f = r.unwrap_err();
        assert!(f.deliberate && f.code == 7 && f.stderr == "x", "{f:?}");
        let (r, _) = drive("[ a = b ] && echo never\n", &[]);
        let f = r.unwrap_err();
        assert!(!f.deliberate && f.code == 1 && f.line == 1, "{f:?}");
        let (r, lines) = drive(
            "echo fine\nprintf 'bar\\r'\nsleep 0.3\nprintf 'baz\\n'\n",
            &[],
        );
        assert!(r.is_ok());
        assert_eq!(
            lines,
            ["fine", "bar", "baz"],
            "a redraw is shown as it stands"
        );
    }

    #[test]
    fn snippets_answer_with_their_output_or_their_reason() {
        let env: Vec<(String, String)> = vec![("X".into(), "v".into())];
        let s = step("echo \"got $X\"\n");
        assert_eq!(run(&Shell::File(s.file.clone()), &env).unwrap(), "got v");
        let no = step("echo why >&2\nexit 3\n");
        assert_eq!(guard(&no.file, &[]).unwrap_err(), "why");
        let yes = step("return 0\n");
        assert!(guard(&yes.file, &[]).is_ok());
    }
}

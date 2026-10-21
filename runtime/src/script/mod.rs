//! The only place this program starts a process. Everything the runtime does is shell, handed
//! the answers as variables and read back as an exit status or stdout.
//!
//! The embedded product is written out once per process, readable by this user only, and every
//! script runs from there with lib.sh in front of it.

mod handover;
mod session;

pub use session::{Event, Session};

use std::os::unix::fs::DirBuilderExt;
use std::os::unix::process::CommandExt;
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
        create(&base)
    })
    .as_ref()
    .map(PathBuf::as_path)
    .map_err(Clone::clone)
}

fn create(base: &Path) -> Result<PathBuf, String> {
    sweep(base);
    let dir = base.join(format!("{}-{}", env!("CARGO_PKG_NAME"), std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::DirBuilder::new()
        .mode(0o700)
        .create(&dir)
        .map_err(|e| format!("{}: {e}", dir.display()))?;
    for (name, bytes) in crate::embedded::FILES {
        let path = dir.join(name);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| format!("{}: {e}", parent.display()))?;
        }
        std::fs::write(&path, bytes).map_err(|e| format!("{name}: {e}"))?;
    }
    Ok(dir)
}

/// Removes the folders of runs no longer running. A run ended by a signal leaves its own, and
/// so does every test run, which never reaches `cleanup`.
fn sweep(base: &Path) {
    let prefix = concat!(env!("CARGO_PKG_NAME"), "-");
    let Ok(entries) = std::fs::read_dir(base) else {
        return;
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let Some(pid) = name
            .to_str()
            .and_then(|n| n.strip_prefix(prefix))
            .and_then(|n| n.parse().ok())
            .and_then(rustix::process::Pid::from_raw)
        else {
            continue;
        };
        let dead = rustix::process::test_kill_process(pid) == Err(rustix::io::Errno::SRCH);
        if dead && entry.file_type().is_ok_and(|t| t.is_dir()) {
            let _ = std::fs::remove_dir_all(entry.path());
        }
    }
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

/// A step, under the trap that reports on fd 3 where it broke: code, file, line, command and the
/// function the line is in. `$3` is the file its own lines are in: the script, or the library for
/// a function. Within a helper of the library, the file and line are the script's that called
/// it. `-e` stays off, since `source` hands back the status of a benign last line. A script that
/// stops itself with `exit` leaves no report, which is how a chosen status is told from a broken
/// command. The DEBUG trap remembers the step's own last line for one that hands back a status
/// without a failing command. Inside `$(…)` or `( … )` the trap ends the subshell alone, and
/// what the enclosing command makes of its status decides: a report from there would be read as
/// the step's own. The command goes on one line, a here-document and a tab in it alike, or the
/// report would come apart.
const STEP: &str = concat!(
    "set -Eo pipefail -T\n",
    "[ -z \"$2\" ] || source \"$2\" || exit $?\n",
    "rt_lib=$2 rt_home=$3\n",
    "rt_failed() {\n",
    "  [ \"$BASH_SUBSHELL\" -eq 0 ] || exit \"$1\"\n",
    "  local f=1 line=$2 fn=\"\" cmd=$3\n",
    "  cmd=${cmd//[$'\\n\\t']/ }\n",
    "  while [ \"${BASH_SOURCE[f]}\" = \"$rt_lib\" ] && [ -n \"${BASH_SOURCE[f + 1]:-}\" ]; do line=${BASH_LINENO[f]}; f=$((f + 1)); done\n",
    "  [ -n \"${BASH_SOURCE[f]}\" ] || return 0\n",
    "  [ \"${BASH_SOURCE[f]}\" != \"$rt_lib\" ] || fn=${FUNCNAME[f]}\n",
    "  printf \"fail\\t%d\\t%s\\t%d\\t%s\\t%s\\n\" \"$1\" \"${BASH_SOURCE[f]}\" \"$line\" \"$cmd\" \"$fn\" >&3\n",
    "  exit \"$1\"\n",
    "}\n",
    "trap 'rt_failed $? \"$LINENO\" \"$BASH_COMMAND\"' ERR\n",
    "trap '[ \"${BASH_SOURCE[0]}\" = \"$rt_home\" ] && { rt_line=$LINENO; rt_cmd=$BASH_COMMAND; rt_fn=${FUNCNAME[0]}; }; :' DEBUG\n",
    "eval \"$1\"\n",
    "c=$?\n",
    "[ \"$rt_home\" = \"$rt_lib\" ] || rt_fn=\"\"\n",
    "rt_cmd=${rt_cmd//[$'\\n\\t']/ }\n",
    "[ \"$c\" -eq 0 ] || printf \"fail\\t%d\\t%s\\t%d\\t%s\\t%s\\n\" \"$c\" \"$rt_home\" \"${rt_line:-0}\" \"$rt_cmd\" \"${rt_fn:-}\" >&3\n",
    "exit $c"
);

/// bash with a wrapper, what it runs as `$1`, the library as `$2`, then `rest`, and the answers.
fn bash(
    wrapper: &str,
    payload: &str,
    rest: &[&str],
    env: &[(String, String)],
) -> Result<Command, String> {
    let mut cmd = Command::new("bash");
    cmd.arg("-c")
        .arg(wrapper)
        .arg("--")
        .arg(payload)
        .arg(lib()?)
        .args(rest);
    cmd.envs(env.iter().map(|(k, v)| (k.as_str(), v.as_str())));
    Ok(cmd)
}

/// A session of its own for a script that runs beside the interface: no terminal to stop at,
/// read from or draw into, and one group that is stopped whole.
fn detached(cmd: &mut Command) -> &mut Command {
    // SAFETY: setsid is async-signal-safe.
    unsafe { cmd.pre_exec(|| rustix::process::setsid().map(drop).map_err(Into::into)) }
}

/// Shutdown and sleep held off through logind for as long as it lives, so a closed lid suspends
/// no run halfway. The lock also ends with this process, should it end without dropping it.
pub struct Hold(rustix::process::Pid);

impl Drop for Hold {
    fn drop(&mut self) {
        let _ = rustix::process::kill_process_group(self.0, rustix::process::Signal::TERM);
    }
}

/// A hold for `why`, or none where logind does not answer, as in a container.
pub fn hold(who: &str, why: &str) -> Option<Hold> {
    let quiet = || {
        let mut cmd = Command::new("systemd-inhibit");
        cmd.stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null());
        cmd
    };
    if !quiet().arg("--list").status().is_ok_and(|s| s.success()) {
        crate::info!("no logind to hold shutdown and sleep off");
        return None;
    }
    let mut cmd = quiet();
    cmd.args([
        "--what=shutdown:sleep",
        "--mode=block",
        &format!("--who={who}"),
        &format!("--why={why}"),
        "tail",
        &format!("--pid={}", std::process::id()),
        "-f",
        "/dev/null",
    ]);
    match detached(&mut cmd).spawn() {
        Ok(child) => rustix::process::Pid::from_raw(child.id() as i32).map(Hold),
        Err(e) => {
            crate::warn!("systemd-inhibit: {e}");
            None
        }
    }
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
    let out = detached(&mut bash(SNIPPET, &piece(shell)?, &[], env)?)
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
pub fn guard(shell: &Shell, env: &[(String, String)]) -> Result<(), String> {
    let out = detached(&mut bash(GUARD, &piece(shell)?, &[], env)?)
        .output()
        .map_err(|e| format!("bash: {e}"))?;
    if out.status.success() {
        return Ok(());
    }
    Err(said(&out))
}

/// One piece of a module's work as this layer takes it: its shell, what a failure calls it,
/// and whether it is an action's rather than a task's.
#[derive(Clone, Debug)]
pub struct Step {
    pub module: String,
    pub name: String,
    pub action: bool,
    pub run: Shell,
}

impl Step {
    /// The file its own lines are in, relative to the product: the library for a function.
    fn file(&self) -> String {
        match &self.run {
            Shell::Call(_) => spec::LIB.to_string(),
            Shell::File(rel) => rel.clone(),
        }
    }
}

/// Starts a step in the background, its output to the log and the events to `sink`.
pub fn start(
    step: Step,
    env: &[(String, String)],
    sink: impl Fn(Event) + Send + Sync + 'static,
) -> Result<Session, String> {
    let home = match &step.run {
        Shell::Call(_) => lib()?,
        Shell::File(rel) => path(rel)?.display().to_string(),
    };
    let cmd = bash(STEP, &piece(&step.run)?, &[&home], env)?;
    Session::spawn(step, cmd, sink)
}

/// Runs an action on the terminal itself, in place of the interface, and waits for it. Nothing
/// is captured or logged: its output is the terminal's.
pub fn handover(step: &Step, env: &[(String, String)]) -> Result<(), Box<Failure>> {
    let payload = piece(&step.run).map_err(|e| Box::new(Failure::new(step, e)))?;
    let cmd = bash(SNIPPET, &payload, &[], env).map_err(|e| Box::new(Failure::new(step, e)))?;
    match handover::run(cmd) {
        Ok(status) if status.success() => Ok(()),
        Ok(status) => Err(Box::new(Failure {
            code: status.code().unwrap_or(1),
            script: step.file(),
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
    /// The function of the library the line is in, where the script is the library.
    pub function: String,
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
            Some(fields) if fields.len() >= 6 && fields[0] == "fail" => {
                f.code = fields[1].parse().unwrap_or(f.code);
                f.script = short(fields[2]);
                f.line = fields[3].parse().unwrap_or(0);
                f.command = fields[4].to_string();
                f.function = fields[5].to_string();
            }
            _ => {
                f.script = step.file();
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
        add(t("Function"), &self.function);
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
        let name = format!("t{}", unique());
        let rel = format!("fixture/{name}.sh");
        let file = dir().unwrap().join(&rel);
        std::fs::create_dir_all(file.parent().unwrap()).unwrap();
        std::fs::write(&file, body).unwrap();
        Step {
            module: "Fixture".into(),
            name: name.clone(),
            action: false,
            run: Shell::File(rel),
        }
    }

    /// A name no other test gets: tests run side by side, and two may start in the same
    /// nanosecond.
    pub fn unique() -> String {
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let n = NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        format!("{}-{n}", std::process::id())
    }

    /// Runs a step to its end and returns the outcome and the lines it drew.
    pub fn drive(body: &str, env: &[(String, String)]) -> (Result<(), Failure>, Vec<String>) {
        let (tx, rx) = std::sync::mpsc::channel();
        let session = start(step(body), env, move |e| drop(tx.send(e))).unwrap();
        let mut lines = Vec::new();
        let deadline = std::time::Instant::now() + Duration::from_secs(10);
        while std::time::Instant::now() < deadline {
            match rx.recv_timeout(Duration::from_millis(50)) {
                Ok(Event::Line(l) | Event::Drawn(l)) => lines.push(l),
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

    /// Held while the hold lives, released once it is dropped. Where logind does not answer, as
    /// in a container, there is nothing to hold and nothing to check.
    #[test]
    fn a_hold_holds_until_it_is_dropped() {
        let who = format!("rt-test-{}", std::process::id());
        let listed = || {
            Command::new("systemd-inhibit")
                .arg("--list")
                .output()
                .ok()
                .filter(|o| o.status.success())
                .map(|o| String::from_utf8_lossy(&o.stdout).contains(&who))
        };
        let Some(false) = listed() else {
            eprintln!("no logind here: nothing held, nothing checked");
            return;
        };
        let until = |want: bool| {
            let deadline = std::time::Instant::now() + Duration::from_secs(10);
            while listed() != Some(want) {
                assert!(std::time::Instant::now() < deadline, "never {want}");
                std::thread::sleep(Duration::from_millis(50));
            }
        };
        let held = hold(&who, "a test").expect("logind answered");
        until(true);
        drop(held);
        until(false);
    }

    #[test]
    fn a_failure_inside_a_helper_names_the_line_that_called_it() {
        let s = step("true\nbroken\n");
        let (tx, rx) = std::sync::mpsc::channel();
        let _session = start(s.clone(), &[], move |e| drop(tx.send(e))).unwrap();
        let f = loop {
            if let Event::Exit(r) = rx.recv_timeout(Duration::from_secs(10)).unwrap() {
                break r.unwrap_err();
            }
        };
        assert_eq!((f.script.clone(), f.line), (s.file(), 2), "{f:?}");
        assert_eq!(
            (f.command.as_str(), f.function.as_str()),
            ("false", ""),
            "{f:?}"
        );
    }

    /// A step that is a function of the library is told by the library's line and the function,
    /// a failing command and a failing last line alike.
    #[test]
    fn a_failing_function_names_its_line_and_itself() {
        use_fixture();
        for (function, line, command) in [("broken", 3, "false"), ("undecided", 6, "[ a = b ]")] {
            let step = Step {
                module: "Fixture".into(),
                name: function.into(),
                action: true,
                run: Shell::Call(function.into()),
            };
            let (tx, rx) = std::sync::mpsc::channel();
            let _session = start(step, &[], move |e| drop(tx.send(e))).unwrap();
            let f = loop {
                if let Event::Exit(r) = rx.recv_timeout(Duration::from_secs(10)).unwrap() {
                    break r.unwrap_err();
                }
            };
            assert_eq!(
                (
                    f.script.as_str(),
                    f.line,
                    f.function.as_str(),
                    f.command.as_str(),
                    f.deliberate
                ),
                ("fixture-lib.sh", line, function, command, false),
                "{f:?}"
            );
        }
    }

    /// A failure inside `$(…)` is the enclosing command's: an assignment fails the script at its
    /// own line, an echo goes on, and neither leaves a report a later stop would be blamed on.
    #[test]
    fn a_failure_inside_a_substitution_is_the_enclosing_commands_to_tell() {
        let (r, _) = drive("echo \"n: $(false)\"\nexit 7\n", &[]);
        let f = r.unwrap_err();
        assert!(f.deliberate && f.code == 7, "{f:?}");
        let (r, _) = drive("echo \"$(false)\"\nfalse\n", &[]);
        let f = r.unwrap_err();
        assert_eq!(
            (f.line, f.command.as_str(), f.deliberate),
            (2, "false", false),
            "{f:?}"
        );
        let (r, _) = drive("x=$(false)\necho never\n", &[]);
        let f = r.unwrap_err();
        assert_eq!((f.line, f.command.as_str()), (1, "x=$(false)"), "{f:?}");
    }

    /// A command over several lines, as one with a here-document, is reported on one.
    #[test]
    fn a_command_over_several_lines_is_reported_on_one() {
        let (r, _) = drive("false <<EOF\nline\nEOF\n", &[]);
        let f = r.unwrap_err();
        assert_eq!((f.line, f.deliberate), (1, false), "{f:?}");
        assert!(f.command.starts_with("false <<EOF line EOF"), "{f:?}");
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
        assert_eq!(run(&s.run, &env).unwrap(), "got v");
        let no = step("echo why >&2\nexit 3\n");
        assert_eq!(guard(&no.run, &[]).unwrap_err(), "why");
        let yes = step("return 0\n");
        assert!(guard(&yes.run, &[]).is_ok());
    }

    /// A stop asks first, and a script that traps it cleans up and goes. One that stays is
    /// killed after the grace. Either way the stop returns once nothing of the script runs.
    #[test]
    fn a_stop_asks_first_and_kills_what_stays() {
        let out = std::env::temp_dir().join(format!("script-stop-{}", unique()));
        let env = vec![("OUT".to_string(), out.display().to_string())];
        for (body, asked) in [
            (
                "trap 'echo asked >\"$OUT\"' TERM\necho \"$$\"\nsleep 30 &\nwait\n",
                true,
            ),
            ("trap '' TERM\necho \"$$\"\nsleep 30 &\nwait\n", false),
        ] {
            let _ = std::fs::remove_file(&out);
            let (tx, rx) = std::sync::mpsc::channel();
            let session = start(step(body), &env, move |e| drop(tx.send(e))).unwrap();
            let group = loop {
                if let Event::Line(l) = rx.recv_timeout(Duration::from_secs(10)).unwrap() {
                    break l;
                }
            };
            session.stop();
            // A zombie is left out: PID 1 of a container may never collect one.
            let ps = Command::new("ps")
                .args(["-e", "-o", "pgid=,stat="])
                .output()
                .unwrap();
            let left: Vec<String> = String::from_utf8_lossy(&ps.stdout)
                .lines()
                .map(str::split_whitespace)
                .filter_map(|mut f| Some((f.next()?.to_string(), f.next()?.to_string())))
                .filter(|(pgid, stat)| *pgid == group && !stat.starts_with('Z'))
                .map(|(_, stat)| stat)
                .collect();
            assert!(left.is_empty(), "{left:?} still run: {body}");
            assert_eq!(out.exists(), asked, "{body}");
        }
        let _ = std::fs::remove_file(&out);
    }

    #[test]
    fn a_line_redrawn_in_place_is_told_from_a_finished_one() {
        let (tx, rx) = std::sync::mpsc::channel();
        let body = "printf '50%%'\nsleep 0.3\nprintf '\\r100%%\\n'\n";
        let _session = start(step(body), &[], move |e| drop(tx.send(e))).unwrap();
        let mut seen = Vec::new();
        loop {
            match rx.recv_timeout(Duration::from_secs(10)).unwrap() {
                Event::Drawn(l) => seen.push(format!("drawn {l}")),
                Event::Line(l) => seen.push(format!("line {l}")),
                Event::Exit(r) => break r.unwrap(),
            }
        }
        assert_eq!(seen, ["drawn 50%", "line 100%"]);
    }

    #[test]
    fn a_start_removes_what_a_run_no_longer_running_left() {
        let base = std::env::temp_dir().join(format!("script-base-{}", unique()));
        let program = env!("CARGO_PKG_NAME");
        let mut gone = Command::new("true").spawn().unwrap();
        gone.wait().unwrap();
        let left = base.join(format!("{program}-{}", gone.id()));
        let running = base.join(format!("{program}-1"));
        let other = base.join(format!("other-{}", gone.id()));
        for d in [&left, &running, &other] {
            std::fs::create_dir_all(d.join("sub")).unwrap();
        }
        let own = create(&base).unwrap();
        assert!(!left.exists(), "a dead run's folder stays");
        assert!(running.exists() && other.exists() && own.exists());
        std::fs::remove_dir_all(&base).unwrap();
    }
}

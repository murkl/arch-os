//! The only place that starts processes. All work is shell, given the answers as variables and
//! read back as exit status or stdout.
//!
//! The embedded product is written out once per process, readable by this user only. Every
//! script runs from there with lib.sh sourced first.

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

/// Removes the folders of dead runs. A run ended by a signal leaves its folder, so does every
/// test run, which never reaches `cleanup`.
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

/// Path of a product file on disk.
fn path(rel: &str) -> Result<PathBuf, String> {
    Ok(dir()?.join(rel))
}

/// Path of lib.sh, empty when the product has none.
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

/// A declared shell as one shell expression.
fn piece(shell: &Shell) -> Result<String, String> {
    Ok(match shell {
        Shell::Call(name) => name.clone(),
        Shell::File(rel) => format!("source {}", quote(&path(rel)?.display().to_string())),
    })
}

/// A snippet, such as an option list or a suggestion. lib.sh is sourced first, so a fault in it
/// is not blamed on the script. No trap, a non-zero status is an answer.
const SNIPPET: &str = "[ -z \"$2\" ] || source \"$2\" || exit $?\neval \"$1\"";

/// A yes or no check, wrapped in a function so `return 0` means yes.
const GUARD: &str =
    "[ -z \"$2\" ] || source \"$2\" || exit $?\neval \"rt_guard() {\n$1\n}\"\nrt_guard\nexit $?";

/// A step under the ERR trap, which reports code, file, line, command and function on fd 3. `$3`
/// is the file of the step's own lines: the script, or lib.sh for a function. A failure in a
/// lib.sh helper reports the calling script's file and line.
/// - `-e` stays off, since `source` returns the status of a benign last line
/// - `exit` leaves no report, which tells a chosen status from a failed command
/// - The DEBUG trap records the step's last own line for a status without a failing command
/// - Inside `$(…)` or `( … )` the trap ends only the subshell and the enclosing command decides,
///   a report from there would count as the step's own
/// - The command is flattened to one line, here-documents and tabs included, or the report
///   splits
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

/// `bash -c wrapper` with the payload as `$1`, lib.sh as `$2`, then `rest`, and the answers.
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

/// Own session for a script beside the interface: no terminal to stop on, read or draw into,
/// and one process group to stop as a whole.
fn detached(cmd: &mut Command) -> &mut Command {
    // SAFETY: setsid is async-signal-safe.
    unsafe { cmd.pre_exec(|| rustix::process::setsid().map(drop).map_err(Into::into)) }
}

/// Blocks shutdown and sleep through logind while alive, so a closed lid never suspends a run
/// halfway. The lock also ends with this process if it exits without dropping it.
pub struct Hold(rustix::process::Pid);

impl Drop for Hold {
    fn drop(&mut self) {
        let _ = rustix::process::kill_process_group(self.0, rustix::process::Signal::TERM);
    }
}

/// None where logind does not answer, as in a container.
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

/// The last stderr lines of a snippet, or its status.
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

/// Runs a snippet and returns its stdout, end trimmed.
pub fn run(shell: &Shell, env: &[(String, String)]) -> Result<String, String> {
    let out = detached(&mut bash(SNIPPET, &piece(shell)?, &[], env)?)
        .output()
        .map_err(|e| format!("bash: {e}"))?;
    if !out.status.success() {
        return Err(said(&out));
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim_end().to_string())
}

/// Snippet output per line, blank lines dropped. Only line ends are trimmed: a leading tab
/// follows an empty value, which is an answer too.
pub fn lines(shell: &Shell, env: &[(String, String)]) -> Result<Vec<String>, String> {
    Ok(run(shell, env)?
        .lines()
        .map(|l| l.trim_end().to_string())
        .filter(|l| !l.trim().is_empty())
        .collect())
}

/// Runs an action as a yes or no check. On no, its stderr is the message shown.
pub fn guard(shell: &Shell, env: &[(String, String)]) -> Result<(), String> {
    let out = detached(&mut bash(GUARD, &piece(shell)?, &[], env)?)
        .output()
        .map_err(|e| format!("bash: {e}"))?;
    if out.status.success() {
        return Ok(());
    }
    Err(said(&out))
}

/// A task or action as this layer runs it. `name` labels a failure.
#[derive(Clone, Debug)]
pub struct Step {
    pub module: String,
    pub name: String,
    pub action: bool,
    pub run: Shell,
}

impl Step {
    /// File of its own lines, relative to the product: lib.sh for a function.
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

/// Runs an action on the terminal in place of the interface and waits for it. Nothing is
/// captured or logged.
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

/// A failed script: module, step, file and line, command and stderr.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Failure {
    pub module: String,
    pub unit: String,
    pub action: bool,
    pub script: String,
    pub line: u32,
    /// The lib.sh function of `line`, when the script is lib.sh.
    pub function: String,
    pub code: i32,
    pub command: String,
    pub stderr: String,
    /// Ended by `exit`, not a failed command, so the status is chosen and may have a text.
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

    /// From the exit status, the first `fail` line of the trap, and stderr.
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

    /// Label and value rows of a failure report. Short wins over exact.
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

/// A script path relative to the product, as its author knows it.
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

    /// The fixture's lib.sh, once a test asked for it.
    pub static LIB: OnceLock<String> = OnceLock::new();

    /// Writes the fixture beside the real product and sources its lib.sh before every script.
    /// Written once: tests run in parallel, and a rewrite empties a file another test's
    /// script is reading.
    pub fn use_fixture() {
        static WRITTEN: OnceLock<()> = OnceLock::new();
        let dir = dir().unwrap();
        WRITTEN.get_or_init(|| {
            for (rel, bytes) in crate::spec::tests::fixture() {
                let path = if rel == "lib.sh" {
                    dir.join("fixture-lib.sh")
                } else {
                    dir.join(rel)
                };
                std::fs::create_dir_all(path.parent().unwrap()).unwrap();
                std::fs::write(&path, bytes).unwrap();
            }
        });
        let _ = LIB.set(dir.join("fixture-lib.sh").display().to_string());
    }

    /// A fixture script step with the fixture's lib.sh, whatever product is embedded.
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

    /// Unique per test: tests run in parallel, two may start in the same nanosecond.
    pub fn unique() -> String {
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let n = NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        format!("{}-{n}", std::process::id())
    }

    /// Runs a step to the end, returns the outcome and its lines.
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

    /// Skipped where logind does not answer, as in a container.
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

    /// A failing command and a failing last line alike.
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

    /// An assignment fails at its own line, an echo goes on, and neither leaves a report a later
    /// stop would be blamed on.
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

    /// A script that traps TERM cleans up and exits, one that ignores it is killed after the
    /// grace period. Either way the stop returns once nothing of it runs.
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
            // Zombies are ignored, PID 1 of a container may never reap them.
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

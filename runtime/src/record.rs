//! The run as a script: every command the tasks record and confirm, under its task's title, after
//! a head that does what the interface did before the run. Written whole on every change, so a
//! task may copy it at any point.

use std::path::{Path, PathBuf};

use crate::spec::{Kind, Setting};
use crate::store::quote;

/// Width of a section ruler, as lib.sh draws its own.
const WIDTH: usize = 80;

/// A password from the environment, else typed twice, as the password page asks it.
const PASSWORD: &str = r#"password() {
    local again=""
    [ -z "${!1:-}" ] || return 0
    while :; do
        read -rsp "$2: " "${1?}" </dev/tty
        read -rsp $'\nRepeat: ' again </dev/tty
        echo
        if [ "${!1}" != "$again" ]; then
            echo 'The two entries do not match.'
        elif [ -n "$again" ]; then
            return 0
        fi
    done
}
"#;

pub struct Record {
    path: PathBuf,
    head: String,
    /// Confirmed commands under their task's title, in run order.
    sections: Vec<(String, Vec<String>)>,
    /// Recorded and not confirmed yet: still running, or failed.
    pending: Option<(String, String)>,
}

impl Record {
    pub fn new(path: &Path, head: String) -> Record {
        let record = Record {
            path: path.to_path_buf(),
            head,
            sections: Vec::new(),
            pending: None,
        };
        record.save();
        record
    }

    /// Task `title` runs `text` next. A command still unconfirmed failed and stays out.
    pub fn command(&mut self, title: &str, text: String) {
        self.pending = Some((title.to_string(), text));
    }

    pub fn confirmed(&mut self) {
        let Some((title, text)) = self.pending.take() else {
            return;
        };
        match self.sections.last_mut() {
            Some((last, commands)) if *last == title => commands.push(text),
            _ => self.sections.push((title, vec![text])),
        }
        self.save();
    }

    fn text(&self) -> String {
        let mut out = self.head.clone();
        for (title, commands) in &self.sections {
            out.push('\n');
            out += &ruler(title);
            for command in commands {
                out += command;
                out.push('\n');
            }
        }
        out
    }

    /// A failure is only logged: the run's work does not depend on its script.
    fn save(&self) {
        if let Err(e) = write(&self.path, &self.text()) {
            crate::error!("{}: {e}", self.path.display());
        }
    }
}

/// Interpreter and strict mode, then `lines` from the module, each password the run asked and
/// its confirmation, opening on No. `confirm` has its placeholders filled.
pub fn head(
    title: &str,
    file: &str,
    lines: &str,
    secrets: &[&Setting],
    confirm: Option<&str>,
) -> String {
    let mut out = format!(
        "#!/usr/bin/env bash\n# Commands of the {title} {}, run on {}.\n# bash {file} repeats the run.\nset -euo pipefail\n",
        crate::version::version(),
        crate::log::now(),
    );
    if !lines.trim().is_empty() {
        out += &format!("\n{}\n", lines.trim_end());
    }
    if !secrets.is_empty() {
        out.push('\n');
        if secrets.iter().any(|s| s.kind == Kind::NewPassword) {
            out += PASSWORD;
        }
        for s in secrets {
            let (name, title) = (&s.name, quote(&s.title));
            out += &match s.kind {
                Kind::NewPassword => format!("password {name} {title}\n"),
                _ => format!(
                    "[ -n \"${{{name}:-}}\" ] || {{ read -rsp {} {name} </dev/tty; echo; }}\n",
                    quote(&format!("{}: ", s.title))
                ),
            };
        }
    }
    if let Some(confirm) = confirm {
        out.push('\n');
        for line in confirm.trim_end().lines() {
            match line.trim() {
                "" => out += "echo\n",
                line => out += &format!("echo {}\n", quote(line)),
            }
        }
        out += "read -rp '[y/N] ' answer </dev/tty\n[[ $answer == [yY] ]]\n";
    }
    out
}

/// `# ─── Title ───…` to the full width.
fn ruler(title: &str) -> String {
    let lead = format!("# ─── {title} ");
    let fill = WIDTH.saturating_sub(lead.chars().count());
    format!("{lead}{}\n", "─".repeat(fill))
}

/// Written beside the file and renamed over it, so a copy never takes half. Executable by its
/// owner only, since it holds the answers.
fn write(path: &Path, text: &str) -> std::io::Result<()> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension("sh.new");
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o700)
        .open(&tmp)?;
    f.write_all(text.as_bytes())?;
    std::fs::rename(&tmp, path)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn secret(name: &str, kind: Kind, title: &str) -> Setting {
        let mut s = crate::spec::loaded().modules[0].settings[0].clone();
        s.name = name.into();
        s.kind = kind;
        s.title = title.into();
        s
    }

    fn file() -> PathBuf {
        let dir = std::env::temp_dir().join(format!("record-{}", crate::script::tests::unique()));
        dir.join("setup.sh")
    }

    /// The head asks what the run asked: passwords, a new one twice, then the confirmation.
    #[test]
    fn the_head_asks_what_the_run_asked() {
        let new = secret("TUX_PASSWORD", Kind::NewPassword, "Password");
        let old = secret("TUX_UNLOCK", Kind::Password, "Disk password");
        let text = head(
            "Setup",
            "setup.sh",
            "loadkeys de\n",
            &[&new, &old],
            Some("Install on sda?\n\nIt's erased."),
        );
        assert!(text.starts_with("#!/usr/bin/env bash\n"), "{text}");
        assert!(
            text.contains("\nset -euo pipefail\n\nloadkeys de\n"),
            "{text}"
        );
        assert!(
            text.contains("\npassword TUX_PASSWORD 'Password'\n"),
            "{text}"
        );
        assert!(
            text.contains("read -rsp 'Disk password: ' TUX_UNLOCK </dev/tty"),
            "{text}"
        );
        assert!(
            text.contains("echo 'Install on sda?'\necho\necho 'It'\\''s erased.'\n"),
            "{text}"
        );
        assert!(text.ends_with("[[ $answer == [yY] ]]\n"), "{text}");
        let check = std::process::Command::new("bash")
            .args(["-n", "-c", &text])
            .output()
            .unwrap();
        assert!(check.status.success(), "{text}");
    }

    /// Only confirmed commands stay, each under its task, and the file is whole after each.
    #[test]
    fn a_failed_command_stays_out() {
        let path = file();
        let mut record = Record::new(&path, head("Setup", "setup.sh", "", &[], None));
        record.command("Prepare the disk", "wipefs -a /dev/sda".into());
        record.confirmed();
        record.command("Prepare the disk", "sbctl enroll-keys -m -f".into());
        record.command("Prepare the disk", "sbctl enroll-keys -m".into());
        record.confirmed();
        record.command("Install the base", "cat >/etc/x <<'EOF'\na\nEOF".into());
        let text = std::fs::read_to_string(&path).unwrap();
        assert_eq!(ruler("Prepare the disk").trim_end().chars().count(), WIDTH);
        assert!(
            text.contains(&format!(
                "\n{}wipefs -a /dev/sda\nsbctl enroll-keys -m\n",
                ruler("Prepare the disk")
            )),
            "{text}"
        );
        assert!(
            !text.contains("-m -f") && !text.contains("Install the base"),
            "{text}"
        );
        record.confirmed();
        let text = std::fs::read_to_string(&path).unwrap();
        assert!(
            text.ends_with(&format!(
                "{}cat >/etc/x <<'EOF'\na\nEOF\n",
                ruler("Install the base")
            )),
            "{text}"
        );
        use std::os::unix::fs::PermissionsExt;
        let mode = std::fs::metadata(&path).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o700);
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }
}

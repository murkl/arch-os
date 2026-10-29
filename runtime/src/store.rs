//! The answers and their file. Shell syntax (`KEY='value' # title`): editable on a bare live
//! system, sourced as is by scripts.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use crate::i18n::t;
use crate::spec::{self, Kind, Module, Preset, Setting};

pub struct Store {
    module: &'static Module,
    values: BTreeMap<String, String>,
    path: PathBuf,
    log: PathBuf,
    dry_run: bool,
    pub language: String,
    /// Answers a reread list no longer offers, with the value it rejected.
    unoffered: BTreeMap<String, String>,
}

impl Store {
    /// Answer file and log in `dir`, named after the module.
    pub fn new(module: &'static Module, dir: &Path, dry_run: bool) -> Store {
        let mut values = BTreeMap::new();
        for s in &module.settings {
            values.insert(s.name.clone(), s.default.clone());
        }
        for a in &module.actions {
            for s in &a.inputs {
                values.insert(s.name.clone(), s.default.clone());
            }
        }
        Store {
            module,
            values,
            path: dir.join(format!("{}.conf", module.id)),
            log: dir.join(format!("{}.log", module.id)),
            dry_run,
            language: String::new(),
            unoffered: BTreeMap::new(),
        }
    }

    pub fn module(&self) -> &'static Module {
        self.module
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn log(&self) -> &Path {
        &self.log
    }

    pub fn dry_run(&self) -> bool {
        self.dry_run
    }

    pub fn exists(&self) -> bool {
        self.path.exists()
    }

    pub fn get(&self, name: &str) -> &str {
        self.values
            .get(name)
            .map(String::as_str)
            .unwrap_or_default()
    }

    /// An action's answer a script wrote into the answer file, read from the file and held
    /// nowhere else.
    pub fn read(&self, name: &str) -> Option<String> {
        let raw = std::fs::read_to_string(&self.path).ok()?;
        raw.lines()
            .filter_map(parse_line)
            .rfind(|(k, _)| k == name)
            .map(|(_, v)| v)
    }

    /// Answer lookup for placeholders and conditions.
    pub fn getter(&self) -> impl Fn(&str) -> String + '_ {
        |name| self.get(name).to_string()
    }

    /// Does not save, a value tried out is not a value settled.
    pub fn set(&mut self, name: &str, value: &str) {
        self.values.insert(name.to_string(), value.to_string());
    }

    /// A missing file is a first run. An invalid value stays for `missing` to ask again.
    pub fn load(&mut self) -> std::io::Result<()> {
        let raw = match std::fs::read_to_string(&self.path) {
            Ok(raw) => raw,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(e) => return Err(e),
        };
        for line in raw.lines() {
            let Some((name, value)) = parse_line(line) else {
                continue;
            };
            if name == spec::LANGUAGE {
                self.language = value;
            } else if let Some(s) = self.module.setting(&name)
                && !s.kind.secret()
            {
                self.values.insert(name, value);
            }
        }
        Ok(())
    }

    /// Writes in declaration order under each group, each answer with its title. Passwords and
    /// derived values stay out, the next run must not read them back.
    pub fn save(&self) -> std::io::Result<()> {
        let mut out = format!("# {}\n", t("Answers, editable by hand."));
        entry(
            &mut out,
            spec::LANGUAGE,
            &self.language,
            t("Interface language"),
        );
        let mut group = "";
        for s in &self.module.settings {
            if s.kind.secret() || s.derived() {
                continue;
            }
            if s.group != group {
                group = &s.group;
                if !group.is_empty() {
                    out += &format!("\n# {}\n", t(group));
                }
            }
            entry(&mut out, &s.name, self.get(&s.name), t(&s.title));
        }
        write(&self.path, &out)
    }

    /// Back to defaults without a file, so the next run is a first run. The log stays, it records
    /// what was done to the machine.
    pub fn reset(&mut self) -> std::io::Result<()> {
        for s in &self.module.settings {
            self.values.insert(s.name.clone(), s.default.clone());
        }
        match std::fs::remove_file(&self.path) {
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e),
            _ => Ok(()),
        }
    }

    /// Every declared variable and the runtime's own, set over the inherited environment.
    /// Contains passwords, so it goes only to child processes.
    pub fn env(&self) -> Vec<(String, String)> {
        let mut env: Vec<(String, String)> = Vec::new();
        for name in self.module.declared() {
            env.push((name.to_string(), self.get(name).to_string()));
        }
        env.push((spec::CONF.into(), self.path.display().to_string()));
        env.push((spec::LOG.into(), self.log.display().to_string()));
        env.push((spec::LANGUAGE.into(), self.language.clone()));
        env.push((spec::VERSION.into(), crate::version::version().into()));
        if self.dry_run {
            env.push((spec::DRY_RUN.into(), spec::TRUE.into()));
        }
        env
    }

    /// The preset's values become ordinary answers.
    pub fn apply(&mut self, preset: &Preset) {
        for (name, value) in &preset.values {
            self.values.insert(name.clone(), value.clone());
        }
    }

    /// Settings that apply and lack a valid answer, in declaration order. Passwords and derived
    /// values are never asked here.
    pub fn missing(&self) -> Vec<&'static Setting> {
        self.module
            .settings
            .iter()
            .filter(|s| !s.kind.secret() && !s.derived() && s.applies(self.getter()))
            .filter(|s| self.invalid(s, self.get(&s.name)).is_some())
            .collect()
    }

    /// Missing settings asked before anything else.
    pub fn upfront(&self) -> Vec<&'static Setting> {
        self.missing().into_iter().filter(|s| s.first).collect()
    }

    /// Passwords entered before a run, in declaration order.
    pub fn secrets(&self) -> Vec<&'static Setting> {
        self.module
            .settings
            .iter()
            .filter(|s| s.kind.secret() && s.applies(self.getter()))
            .collect()
    }

    /// Settings the dashboard shows, in declaration order.
    pub fn visible(&self) -> Vec<&'static Setting> {
        self.module
            .settings
            .iter()
            .filter(|s| !s.kind.secret() && !s.derived() && s.applies(self.getter()))
            .collect()
    }

    /// The reread list no longer offers the current answer.
    pub fn unoffer(&mut self, name: &str) {
        self.unoffered
            .insert(name.to_string(), self.get(name).to_string());
    }

    pub fn reoffer(&mut self, name: &str) {
        self.unoffered.remove(name);
    }

    /// The error for an invalid value. Typed and hand-edited values follow the same rules.
    pub fn invalid(&self, s: &Setting, value: &str) -> Option<String> {
        if value.is_empty() {
            return s.required.then(|| why(s));
        }
        if self
            .unoffered
            .get(&s.name)
            .is_some_and(|turned| turned == value)
        {
            return Some(match &s.error {
                Some(e) => t(e),
                None => t("Not one of the options."),
            });
        }
        let allowed = match s.kind {
            Kind::Bool => value == spec::TRUE || value == spec::FALSE,
            _ if !s.options.is_empty() => s.options.iter().any(|o| o == value),
            _ => true,
        };
        (!allowed || !s.matches(value)).then(|| why(s))
    }

    /// A bool in words, an empty answer as a dash.
    pub fn display(&self, s: &Setting) -> String {
        match self.get(&s.name) {
            "" => "—".into(),
            value => label(value),
        }
    }

    /// Clears the passwords, so none stays in memory after the run that needed it.
    pub fn forget(&mut self) {
        for name in self.module.declared() {
            let secret = self
                .module
                .setting(name)
                .map(|s| s.kind.secret())
                .or_else(|| {
                    self.module
                        .actions
                        .iter()
                        .flat_map(|a| &a.inputs)
                        .find(|s| s.name == name)
                        .map(|s| s.kind.secret())
                })
                .unwrap_or(false);
            if secret {
                self.values.insert(name.to_string(), String::new());
            }
        }
    }
}

/// The setting's own error, else the broken rule.
fn why(s: &Setting) -> String {
    match &s.error {
        Some(e) => t(e),
        None if s.pattern.is_some() => t("Invalid format."),
        None => t("An answer is required."),
    }
}

/// `true` and `false` translated, anything else as is.
pub fn label(value: &str) -> String {
    match value {
        spec::TRUE => t("Yes"),
        spec::FALSE => t("No"),
        other => other.to_string(),
    }
}

fn entry(out: &mut String, name: &str, value: &str, title: String) {
    *out += &format!("{name}={}", quote(value));
    if !title.trim().is_empty() {
        *out += &format!(" # {}", title.trim());
    }
    out.push('\n');
}

/// Single quotes take no escapes, so a quote closes, escapes and reopens.
pub fn quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', r"'\''"))
}

/// Written beside the file and renamed over it, so an interrupted run never leaves half a file.
/// 0600, since answers may be private.
fn write(path: &Path, content: &str) -> std::io::Result<()> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension("conf.new");
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&tmp)?;
    f.write_all(content.as_bytes())?;
    f.sync_all()?;
    std::fs::rename(&tmp, path)
}

/// `KEY=value`, the value single-quoted, double-quoted or bare.
pub fn parse_line(line: &str) -> Option<(String, String)> {
    let line = line.trim();
    if line.is_empty() || line.starts_with('#') {
        return None;
    }
    let (name, rest) = line.split_once('=')?;
    let name = name.trim();
    if name.is_empty() {
        return None;
    }
    let rest = rest.trim_start();
    let value = if let Some(q) = rest.strip_prefix('\'') {
        unquote_single(q)
    } else if let Some(q) = rest.strip_prefix('"') {
        q.split('"').next().unwrap_or_default().to_string()
    } else {
        rest.split(' ')
            .next()
            .unwrap_or_default()
            .trim()
            .to_string()
    };
    Some((name.to_string(), value))
}

fn unquote_single(mut s: &str) -> String {
    let mut out = String::new();
    loop {
        let Some(i) = s.find('\'') else {
            out.push_str(s);
            return out;
        };
        out.push_str(&s[..i]);
        let rest = &s[i + 1..];
        let Some(after) = rest.strip_prefix(r"\''") else {
            return out;
        };
        out.push('\'');
        s = after;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn module() -> &'static Module {
        let loaded: &'static spec::Loaded =
            Box::leak(Box::new(spec::load(&spec::tests::fixture()).unwrap()));
        loaded.module("setup").unwrap()
    }

    fn store(name: &str) -> Store {
        let dir = std::env::temp_dir().join(format!("store-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        Store::new(module(), &dir, false)
    }

    #[test]
    fn reads_what_a_script_answered_under_no_setting() {
        let s = store("read");
        std::fs::write(
            s.path(),
            "TUX_HOST='box' # Hostname\nTUX_URL='https://x/1'\n",
        )
        .unwrap();
        assert_eq!(s.read("TUX_URL").as_deref(), Some("https://x/1"));
        assert_eq!(s.read("TUX_NONE"), None);
    }

    #[test]
    fn quotes_round_trip() {
        for value in ["plain", "it's", "a 'b' c", "", "\"q\""] {
            let line = format!("X={} # title", quote(value));
            assert_eq!(
                parse_line(&line),
                Some(("X".into(), value.into())),
                "{line}"
            );
        }
        assert_eq!(
            parse_line("Y=\"two words\" # t"),
            Some(("Y".into(), "two words".into()))
        );
        assert_eq!(parse_line("Z=bare word"), Some(("Z".into(), "bare".into())));
        assert_eq!(parse_line("# comment"), None);
        assert_eq!(parse_line("=x"), None);
    }

    #[test]
    fn missing_follows_the_rules_and_the_answers() {
        let mut s = store("missing");
        fn names(v: Vec<&'static Setting>) -> Vec<&'static str> {
            v.iter().map(|s| s.name.as_str()).collect()
        }
        assert_eq!(names(s.upfront()), ["TUX_KEYMAP"]);
        assert_eq!(
            names(s.missing()),
            [
                "TUX_KEYMAP",
                "TUX_HOST",
                "TUX_DESKTOP",
                "TUX_DRIVER",
                "TUX_DISK"
            ],
            "an unanswered desktop is not none"
        );
        s.set("TUX_KEYMAP", "de");
        s.set("TUX_HOST", "Tux");
        s.set("TUX_DESKTOP", "gnome");
        assert_eq!(
            names(s.missing()),
            ["TUX_HOST", "TUX_DRIVER", "TUX_DISK"],
            "a wrong format and an opened question"
        );
        let host = module().setting("TUX_HOST").unwrap();
        assert_eq!(
            s.invalid(host, "Tux").as_deref(),
            Some("Lower case letters, digits and - only.")
        );
        s.set("TUX_HOST", "tux");
        s.set("TUX_DRIVER", "free");
        s.set("TUX_DISK", "sda");
        assert!(s.missing().is_empty());
        s.unoffer("TUX_DISK");
        assert_eq!(names(s.missing()), ["TUX_DISK"]);
        s.reoffer("TUX_DISK");
        assert!(s.missing().is_empty());
        assert_eq!(names(s.secrets()), ["TUX_PASSWORD"]);
        assert!(
            !names(s.visible()).contains(&"TUX_VM"),
            "derived values are read, not shown"
        );
    }

    #[test]
    fn saves_and_loads_without_passwords() {
        let mut s = store("save");
        s.language = "de".into();
        s.set("TUX_HOST", "tux");
        s.set("TUX_PASSWORD", "secret");
        s.set("TUX_ENCRYPT", "false");
        s.save().unwrap();
        let text = std::fs::read_to_string(s.path()).unwrap();
        assert!(text.contains("MODULE_LANGUAGE='de'"), "{text}");
        assert!(
            text.contains("TUX_HOST='tux' # Hostname") && !text.contains("secret"),
            "{text}"
        );
        assert!(text.contains("\n# System\n"), "{text}");
        let mut again = Store::new(module(), s.path().parent().unwrap(), true);
        again.load().unwrap();
        assert_eq!(
            (
                again.get("TUX_HOST"),
                again.get("TUX_ENCRYPT"),
                again.language.as_str()
            ),
            ("tux", "false", "de")
        );
        let env = again.env();
        assert!(env.contains(&("DRY_RUN".to_string(), "true".to_string())));
        assert!(
            env.iter()
                .any(|(k, v)| k == "MODULE_CONF" && v.ends_with("setup.conf"))
        );
        assert!(
            env.iter().any(|(k, v)| k == "TUX_NOTE" && v.is_empty()),
            "inputs and answers of actions are declared"
        );
        s.forget();
        assert_eq!(s.get("TUX_PASSWORD"), "");
        s.reset().unwrap();
        assert!(!s.exists() && s.get("TUX_HOST").is_empty() && s.get("TUX_ENCRYPT") == "true");
    }
}

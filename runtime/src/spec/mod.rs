//! The declarations of the product and its modules, read and checked once. Nothing outside this
//! module knows the yaml.
//!
//! A product is `product.yaml` and `lib.sh` beside the modules, each a folder with a
//! `module.yaml` and a `tasks/<task>/` folder per task. A module that loads runs: an authoring
//! mistake fails the tests, never silently at run time.

pub mod condition;
pub mod order;
pub mod text;

pub use condition::Condition;

use regex_lite::Regex;
use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet};
use std::sync::OnceLock;
use std::time::Duration;

pub const PRODUCT: &str = "product.yaml";
pub const LIB: &str = "lib.sh";
pub const MODULE: &str = "module.yaml";

/// Prefix of the variables the runtime sets, which no setting may take.
pub const RESERVED: &str = "MODULE_";
pub const DRY_RUN: &str = "DRY_RUN";
pub const CONF: &str = "MODULE_CONF";
pub const LOG: &str = "MODULE_LOG";
pub const LANGUAGE: &str = "MODULE_LANGUAGE";
pub const VERSION: &str = "MODULE_VERSION";

/// Bool answers, written to the answer file and compared by scripts verbatim.
pub const TRUE: &str = "true";
pub const FALSE: &str = "false";
/// The answer that picks nothing, shown like an empty one.
pub const NONE: &str = "none";

// ─── The model ───────────────────────────────────────────────────────────────

/// What belongs to no single module.
#[derive(Clone, Debug, PartialEq)]
pub struct Product {
    /// Heading of every page. Not translated, it is a name.
    pub title: String,
    pub accent: Option<Rgb>,
    /// The accent as one of the 16 console slots, by name. The console palette decides the
    /// actual color.
    pub console_accent: Option<String>,
    /// Background of the selected row. `console_surface` is its console slot.
    pub surface: Option<Rgb>,
    pub console_surface: Option<String>,
    /// The wordmark, line by line. Everything above the first blank line is the eyebrow.
    pub logo: Vec<String>,
    pub status: Option<Status>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rgb(pub u8, pub u8, pub u8);

/// Header status from the exit status of `check`.
#[derive(Clone, Debug, PartialEq)]
pub struct Status {
    pub check: Shell,
    pub every: Duration,
    pub pass: String,
    pub fail: String,
}

/// A lib.sh function, the only shell the yaml names, or a task script by its product path.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Shell {
    Call(String),
    File(String),
}

#[derive(Clone, Debug, PartialEq)]
pub struct Module {
    /// The folder name: command line argument and name of the answer file and log.
    pub id: String,
    pub title: String,
    /// Title of the dashboard row that starts the run.
    pub start: String,
    /// Asked after the passwords, before the run: the question, then the consequence.
    pub confirm: Option<String>,
    /// Shown after a finished run, the headline first.
    pub report: Option<String>,
    /// Actions that must succeed before the run. The first failure blocks it with a page.
    pub requires: Vec<String>,
    pub dashboard: Vec<Entry>,
    /// The group that lists the interface language first.
    pub language: Option<String>,
    pub on: On,
    /// Text per exit status of any of its scripts, the headline first.
    pub errors: BTreeMap<i32, String>,
    pub stages: Vec<String>,
    pub presets: Vec<Preset>,
    pub settings: Vec<Setting>,
    /// In run order: by stage, within a stage by `needs`.
    pub tasks: Vec<Task>,
    pub actions: Vec<Action>,
}

/// A dashboard row: built in, or an action by name.
#[derive(Clone, Debug, PartialEq)]
pub enum Entry {
    Start,
    Settings,
    Reset,
    Action(String),
}

/// Built-in dashboard rows by name. No action may take one.
const ENTRIES: [(&str, Entry); 3] = [
    ("start", Entry::Start),
    ("settings", Entry::Settings),
    ("reset", Entry::Reset),
];

/// Action names offered on leave, failure and success.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct On {
    pub leave: Vec<String>,
    pub failure: Vec<String>,
    pub success: Vec<String>,
}

/// Offered on a first run: a set of answers, or the action that fetches them.
#[derive(Clone, Debug, PartialEq)]
pub struct Preset {
    pub title: String,
    pub description: String,
    pub values: BTreeMap<String, String>,
    pub action: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Text,
    Bool,
    List,
    OpenList,
    Password,
    NewPassword,
}

impl Kind {
    pub const ALL: [(&'static str, Kind); 6] = [
        ("text", Kind::Text),
        ("bool", Kind::Bool),
        ("list", Kind::List),
        ("open-list", Kind::OpenList),
        ("password", Kind::Password),
        ("new-password", Kind::NewPassword),
    ];

    fn parse(s: &str) -> Option<Kind> {
        Kind::ALL.iter().find(|(n, _)| *n == s).map(|(_, k)| *k)
    }

    /// Keys only some kinds take. Any other is refused, nothing would read it.
    fn takes(self) -> &'static [&'static str] {
        match self {
            Kind::Text => &["default", "prefill", "value-from", "pattern"],
            Kind::Bool => &["default", "value-from"],
            Kind::List | Kind::OpenList => &[
                "options",
                "options-from",
                "filter",
                "default",
                "prefill",
                "pattern",
            ],
            Kind::Password => &["check"],
            Kind::NewPassword => &[],
        }
    }

    pub fn listed(self) -> bool {
        matches!(self, Kind::List | Kind::OpenList)
    }

    /// Never stored: asked right before the run that needs it, then forgotten.
    pub fn secret(self) -> bool {
        matches!(self, Kind::Password | Kind::NewPassword)
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Filter {
    #[default]
    Collapsed,
    Open,
}

/// A setting and the rules for a valid answer. The rules hold for typed and hand-edited answers
/// alike.
#[derive(Clone, Debug)]
pub struct Setting {
    pub name: String,
    pub kind: Kind,
    pub title: String,
    pub description: String,
    /// Dashboard heading.
    pub group: String,
    pub required: bool,
    pub default: String,
    pub options: Vec<String>,
    pub options_from: Option<Shell>,
    /// Printed instead of asked: read on open and on every answer change, never shown or stored.
    pub value_from: Option<Shell>,
    /// Prints a suggestion. Still asked.
    pub prefill: Option<Shell>,
    /// Applies the answer to this machine as it is given, such as a keymap.
    pub apply: Option<Shell>,
    /// Verifies a password before it is accepted.
    pub check: Option<Shell>,
    /// Asked before anything else, with the filter open, since no keymap is set yet.
    pub first: bool,
    pub filter: Filter,
    pub pattern: Option<Regex>,
    /// Message for an invalid answer.
    pub error: Option<String>,
    pub when: Vec<Condition>,
}

impl PartialEq for Setting {
    fn eq(&self, other: &Setting) -> bool {
        self.name == other.name
    }
}

impl Setting {
    /// Read off the machine rather than asked.
    pub fn derived(&self) -> bool {
        self.value_from.is_some()
    }

    /// A setting asked first opens with the filter, no keymap is set to type `/` on.
    pub fn filter(&self) -> Filter {
        if self.first {
            Filter::Open
        } else {
            self.filter
        }
    }

    pub fn applies(&self, get: impl Fn(&str) -> String) -> bool {
        condition::hold_all(&self.when, get)
    }

    pub fn matches(&self, value: &str) -> bool {
        self.pattern.as_ref().is_none_or(|re| re.is_match(value))
    }
}

/// A question a task asks mid-run, for a value known only after earlier work. Always a list,
/// never stored. An empty list skips the task.
#[derive(Clone, Debug, PartialEq)]
pub struct Ask {
    pub name: String,
    pub title: String,
    pub description: String,
    pub filter: Filter,
    pub options: Vec<String>,
    pub options_from: Option<Shell>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Task {
    /// Key under its stage, referenced by `needs` and `yes-after`.
    pub id: String,
    pub stage: String,
    /// Its folder in the product: `installer/tasks/partition`.
    pub dir: String,
    pub title: String,
    pub needs: Vec<String>,
    pub when: Vec<Condition>,
    pub asks: Option<Ask>,
    /// A yes or no before it runs, opening on No. No skips it.
    pub confirm: Option<String>,
    /// Earlier tasks. If one ran in this run, `confirm` opens on Yes.
    pub yes_after: Vec<String>,
    /// Page the run stops on afterwards, the first paragraph is the headline.
    pub report: Option<String>,
    /// Shows its last output line under it while it runs.
    pub progress: bool,
    /// Runs on a dry run too, reading `DRY_RUN` itself.
    pub simulates: bool,
    pub allow_failure: bool,
    pub errors: BTreeMap<i32, String>,
    /// Variables its scripts get in the interface language, for text the task
    /// writes into the system.
    pub texts: BTreeMap<String, String>,
    /// It has a `test.sh`.
    pub test: bool,
}

impl Task {
    pub fn script(&self) -> Shell {
        Shell::File(format!("{}/task.sh", self.dir))
    }

    pub fn test_script(&self) -> Shell {
        Shell::File(format!("{}/test.sh", self.dir))
    }

    pub fn applies(&self, get: impl Fn(&str) -> String) -> bool {
        condition::hold_all(&self.when, get)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Action {
    pub id: String,
    /// A lib.sh function, exit 0 is success.
    pub run: Shell,
    pub title: String,
    /// Text under its row. Choosing the row is the consent, so it states what leaves the
    /// machine.
    pub description: String,
    /// Dashboard heading.
    pub group: Option<String>,
    /// Shown on failure: as the page that blocks the run, or as the headline.
    pub error: Option<String>,
    /// Actions that must succeed for this one to be offered.
    pub requires: Vec<String>,
    /// Opened on failure: the first one this machine offers.
    pub on_failure: Vec<String>,
    /// Asked before it runs, a page each, kept for this session only.
    pub inputs: Vec<Setting>,
    pub confirm: Option<String>,
    pub report: Option<String>,
    /// Variable its script writes, shown on the report as a QR code.
    pub qr: Option<String>,
    /// Runs in the terminal instead of a page.
    pub tty: bool,
    pub simulates: bool,
    pub errors: BTreeMap<i32, String>,
}

impl Module {
    pub fn setting(&self, name: &str) -> Option<&Setting> {
        self.settings.iter().find(|s| s.name == name)
    }

    pub fn action(&self, id: &str) -> Option<&Action> {
        self.actions.iter().find(|a| a.id == id)
    }

    pub fn task(&self, id: &str) -> Option<&Task> {
        self.tasks.iter().find(|t| t.id == id)
    }

    pub fn named(&self, names: &[String]) -> Vec<&Action> {
        names.iter().filter_map(|n| self.action(n)).collect()
    }

    /// Every variable a script may get: settings, action inputs and answers, task questions.
    pub fn declared(&self) -> Vec<&str> {
        let mut out: Vec<&str> = self.settings.iter().map(|s| s.name.as_str()).collect();
        for a in &self.actions {
            out.extend(a.inputs.iter().map(|s| s.name.as_str()));
            out.extend(a.qr.as_deref());
        }
        out.extend(
            self.tasks
                .iter()
                .filter_map(|t| t.asks.as_ref())
                .map(|a| a.name.as_str()),
        );
        out
    }

    /// Text for exit status `code`: the unit's own, else the module's.
    pub fn told<'a>(&'a self, own: &'a BTreeMap<i32, String>, code: i32) -> Option<&'a str> {
        own.get(&code)
            .or_else(|| self.errors.get(&code))
            .map(String::as_str)
    }

    /// Leaving asks what to do with the machine. Leave actions mean it booted for this module.
    pub fn leaves(&self) -> bool {
        !self.on.leave.is_empty()
    }

    /// Every text of this module once, in order: what a catalog translates.
    pub fn texts(&self) -> Vec<String> {
        let mut out: Vec<String> = Vec::new();
        let mut add = |s: &str| {
            if !s.is_empty() && !out.iter().any(|o| o == s) {
                out.push(s.to_string());
            }
        };
        add(&self.title);
        add(&self.start);
        add(self.confirm.as_deref().unwrap_or_default());
        add(self.report.as_deref().unwrap_or_default());
        for p in &self.presets {
            add(&p.title);
            add(&p.description);
        }
        let setting = |add: &mut dyn FnMut(&str), s: &Setting| {
            add(&s.title);
            add(&s.description);
            add(&s.group);
            add(s.error.as_deref().unwrap_or_default());
        };
        for s in &self.settings {
            setting(&mut add, s);
        }
        self.errors.values().for_each(|e| add(e));
        for t in &self.tasks {
            add(&t.title);
            if let Some(a) = &t.asks {
                add(&a.title);
                add(&a.description);
            }
            add(t.confirm.as_deref().unwrap_or_default());
            add(t.report.as_deref().unwrap_or_default());
            t.errors.values().for_each(|e| add(e));
            t.texts.values().for_each(|e| add(e));
        }
        for a in &self.actions {
            add(&a.title);
            add(&a.description);
            add(a.group.as_deref().unwrap_or_default());
            add(a.error.as_deref().unwrap_or_default());
            add(a.confirm.as_deref().unwrap_or_default());
            add(a.report.as_deref().unwrap_or_default());
            a.errors.values().for_each(|e| add(e));
            for s in &a.inputs {
                setting(&mut add, s);
            }
        }
        out
    }
}

#[derive(Debug)]
pub struct Loaded {
    pub product: Product,
    pub modules: Vec<Module>,
    /// The product has a lib.sh.
    pub lib: bool,
}

impl Loaded {
    pub fn module(&self, id: &str) -> Option<&Module> {
        self.modules.iter().find(|m| m.id == id)
    }

    pub fn texts(&self) -> Vec<String> {
        let mut out: Vec<String> = Vec::new();
        if let Some(s) = &self.product.status {
            out.extend(
                [s.pass.clone(), s.fail.clone()]
                    .into_iter()
                    .filter(|t| !t.is_empty()),
            );
        }
        for m in &self.modules {
            for t in m.texts() {
                if !out.contains(&t) {
                    out.push(t);
                }
            }
        }
        out
    }
}

/// The embedded product, loaded once. The tests fail on a product that does not load, so the
/// panic never ships.
pub fn loaded() -> &'static Loaded {
    static LOADED: OnceLock<Loaded> = OnceLock::new();
    LOADED.get_or_init(|| {
        // Without a product beside the crate, the tests run on the fixture.
        #[cfg(test)]
        if crate::embedded::FILES.is_empty() {
            return load(&tests::fixture()).unwrap_or_else(|e| panic!("{e}"));
        }
        load(crate::embedded::FILES).unwrap_or_else(|e| panic!("{e}"))
    })
}

// ─── The yaml as written ─────────────────────────────────────────────────────

/// Any scalar as text: `default: true` is natural yaml, and every answer ends up in an
/// environment variable.
#[derive(Deserialize)]
#[serde(untagged)]
enum Scalar {
    Bool(bool),
    Int(i64),
    Float(f64),
    Str(String),
}

impl Scalar {
    fn text(&self) -> String {
        match self {
            Scalar::Bool(b) => b.to_string(),
            Scalar::Int(i) => i.to_string(),
            Scalar::Float(f) => f.to_string(),
            Scalar::Str(s) => s.clone(),
        }
    }
}

/// `when:` as one line or a list.
#[derive(Deserialize, Default)]
#[serde(untagged)]
enum When {
    #[default]
    None,
    One(String),
    Many(Vec<String>),
}

impl When {
    fn lines(&self) -> Vec<&str> {
        match self {
            When::None => Vec::new(),
            When::One(s) => vec![s.as_str()],
            When::Many(v) => v.iter().map(String::as_str).collect(),
        }
    }
}

/// A map in written order, which orders the stages and their tasks.
struct Ordered<T>(Vec<(String, T)>);

impl<T> Default for Ordered<T> {
    fn default() -> Self {
        Ordered(Vec::new())
    }
}

impl<'de, T: Deserialize<'de>> Deserialize<'de> for Ordered<T> {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        struct Visit<T>(std::marker::PhantomData<T>);
        impl<'de, T: Deserialize<'de>> serde::de::Visitor<'de> for Visit<T> {
            type Value = Ordered<T>;
            fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
                f.write_str("a map")
            }
            fn visit_map<A: serde::de::MapAccess<'de>>(
                self,
                mut map: A,
            ) -> Result<Ordered<T>, A::Error> {
                let mut out = Vec::new();
                while let Some(entry) = map.next_entry()? {
                    out.push(entry);
                }
                Ok(Ordered(out))
            }
        }
        d.deserialize_map(Visit(std::marker::PhantomData))
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct ProductFile {
    title: String,
    accent: Option<String>,
    console_accent: Option<String>,
    surface: Option<String>,
    console_surface: Option<String>,
    logo: Option<String>,
    status: Option<StatusFile>,
    #[serde(default)]
    actions: BTreeMap<String, ActionFile>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct StatusFile {
    check: String,
    every: Option<u64>,
    pass: Option<String>,
    fail: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct ModuleFile {
    title: String,
    start: Option<String>,
    confirm: Option<String>,
    report: Option<String>,
    #[serde(default)]
    requires: Vec<String>,
    dashboard: Vec<String>,
    language: Option<String>,
    #[serde(default)]
    on: OnFile,
    #[serde(default)]
    errors: BTreeMap<i32, String>,
    #[serde(default)]
    actions: BTreeMap<String, ActionFile>,
    #[serde(default)]
    stages: Ordered<Ordered<TaskFile>>,
    #[serde(default)]
    presets: Vec<PresetFile>,
    #[serde(default)]
    settings: Ordered<Vec<SettingFile>>,
}

#[derive(Deserialize, Default)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct OnFile {
    #[serde(default)]
    leave: Vec<String>,
    #[serde(default)]
    failure: Vec<String>,
    #[serde(default)]
    success: Vec<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct PresetFile {
    title: String,
    description: Option<String>,
    #[serde(default)]
    values: BTreeMap<String, Scalar>,
    action: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct SettingFile {
    name: String,
    #[serde(rename = "type")]
    kind: Option<String>,
    title: Option<String>,
    description: Option<String>,
    #[serde(default)]
    required: bool,
    default: Option<Scalar>,
    #[serde(default)]
    options: Vec<String>,
    options_from: Option<String>,
    value_from: Option<String>,
    prefill: Option<String>,
    apply: Option<String>,
    check: Option<String>,
    #[serde(default)]
    first: bool,
    filter: Option<String>,
    pattern: Option<String>,
    error: Option<String>,
    #[serde(default)]
    when: When,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct TaskFile {
    title: String,
    #[serde(default)]
    needs: Vec<String>,
    #[serde(default)]
    when: When,
    asks: Option<AskFile>,
    confirm: Option<String>,
    #[serde(default)]
    yes_after: Vec<String>,
    report: Option<String>,
    #[serde(default)]
    progress: bool,
    #[serde(default)]
    simulates: bool,
    #[serde(default)]
    allow_failure: bool,
    #[serde(default)]
    errors: BTreeMap<i32, String>,
    #[serde(default)]
    texts: BTreeMap<String, String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct AskFile {
    name: String,
    title: String,
    description: Option<String>,
    filter: Option<String>,
    #[serde(default)]
    options: Vec<String>,
    options_from: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct ActionFile {
    title: String,
    description: Option<String>,
    group: Option<String>,
    error: Option<String>,
    run: String,
    #[serde(default)]
    requires: Vec<String>,
    #[serde(default)]
    on: ActionOnFile,
    #[serde(default)]
    inputs: Vec<SettingFile>,
    confirm: Option<String>,
    report: Option<String>,
    qr: Option<String>,
    #[serde(default)]
    tty: bool,
    #[serde(default)]
    simulates: bool,
    #[serde(default)]
    errors: BTreeMap<i32, String>,
}

#[derive(Deserialize, Default)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct ActionOnFile {
    #[serde(default)]
    failure: Vec<String>,
}

// ─── Loading ─────────────────────────────────────────────────────────────────

struct Files<'a>(&'a [(&'a str, &'a [u8])]);

impl Files<'_> {
    fn has(&self, path: &str) -> bool {
        self.0.iter().any(|(f, _)| *f == path)
    }

    fn text(&self, path: &str) -> Result<&str, String> {
        let (_, bytes) = self
            .0
            .iter()
            .find(|(f, _)| *f == path)
            .ok_or_else(|| format!("{path}: no such file"))?;
        std::str::from_utf8(bytes).map_err(|_| format!("{path}: not UTF-8"))
    }

    /// The folders directly under `prefix`, in name order.
    fn dirs(&self, prefix: &str) -> Vec<String> {
        let mut out: BTreeSet<String> = BTreeSet::new();
        for (f, _) in self.0 {
            if let Some(rest) = f.strip_prefix(prefix)
                && let Some((dir, _)) = rest.split_once('/')
            {
                out.insert(dir.to_string());
            }
        }
        out.into_iter().collect()
    }

    /// A file directly under `prefix`, if any.
    fn loose(&self, prefix: &str) -> Option<&str> {
        self.0
            .iter()
            .filter_map(|(f, _)| f.strip_prefix(prefix))
            .find(|rest| !rest.contains('/'))
    }
}

fn yaml<T: for<'de> Deserialize<'de>>(files: &Files, path: &str) -> Result<T, String> {
    serde_saphyr::from_str(files.text(path)?).map_err(|e| format!("{path}: {e}"))
}

pub fn load(files: &[(&str, &[u8])]) -> Result<Loaded, String> {
    let files = Files(files);
    let lib = files.has(LIB);
    let functions = if lib {
        functions(files.text(LIB)?)
    } else {
        BTreeSet::new()
    };
    let (product, shared) = product(&files, &functions)?;
    let mut modules = Vec::new();
    for id in files.dirs("") {
        if id == "locales" || !files.has(&format!("{id}/{MODULE}")) {
            continue;
        }
        modules.push(module(&files, &id, &functions, &shared)?);
    }
    if let Some(a) = shared
        .iter()
        .find(|a| modules.iter().all(|m| m.action(&a.id).is_none()))
    {
        return Err(format!(
            "{PRODUCT}: actions: {}: not named in any {MODULE}",
            a.id
        ));
    }
    Ok(Loaded {
        product,
        modules,
        lib,
    })
}

/// Functions lib.sh defines, parsed, not run.
fn functions(lib: &str) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    for line in lib.lines() {
        let line = line.trim_start();
        let name = match line.strip_prefix("function ") {
            Some(rest) => rest.split(['(', ' ', '\t']).next().unwrap_or_default(),
            None => match line.split_once("()") {
                Some((name, _)) => name.trim_end(),
                None => continue,
            },
        };
        if is_name(name) {
            out.insert(name.to_string());
        }
    }
    out
}

fn is_name(s: &str) -> bool {
    let mut chars = s.chars();
    chars
        .next()
        .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
        && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
}

/// A lib.sh function written `name()`.
fn shell(expr: &str, functions: &BTreeSet<String>) -> Result<Shell, String> {
    let expr = expr.trim();
    let Some(name) = expr.strip_suffix("()").filter(|n| is_name(n)) else {
        return Err(format!("{expr:?} is not written name()"));
    };
    if !functions.contains(name) {
        return Err(format!("{name}() is not a function in {LIB}"));
    }
    Ok(Shell::Call(name.to_string()))
}

fn opt_shell(
    expr: &Option<String>,
    key: &str,
    functions: &BTreeSet<String>,
) -> Result<Option<Shell>, String> {
    match expr {
        Some(e) => shell(e, functions)
            .map(Some)
            .map_err(|err| format!("{key}: {err}")),
        None => Ok(None),
    }
}

/// Console slots a product may name: all but black and bright-black, the background and the
/// muted text.
pub const SLOTS: [&str; 14] = [
    "red",
    "green",
    "yellow",
    "blue",
    "magenta",
    "cyan",
    "white",
    "bright-red",
    "bright-green",
    "bright-yellow",
    "bright-blue",
    "bright-magenta",
    "bright-cyan",
    "bright-white",
];

fn parse_rgb(s: &str) -> Option<Rgb> {
    let hex = s.strip_prefix('#')?;
    if hex.len() != 6 || !hex.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    let byte = |i: usize| u8::from_str_radix(&hex[i..i + 2], 16).ok();
    Some(Rgb(byte(0)?, byte(2)?, byte(4)?))
}

/// The product and its shared actions.
fn product(files: &Files, functions: &BTreeSet<String>) -> Result<(Product, Vec<Action>), String> {
    if !files.has(PRODUCT) {
        return Err(format!("{PRODUCT}: no product beside the runtime"));
    }
    let f: ProductFile = yaml(files, PRODUCT)?;
    let rgb = |key: &str, value: &Option<String>| match value {
        Some(v) => parse_rgb(v)
            .map(Some)
            .ok_or_else(|| format!("{PRODUCT}: {key}: {v:?} is not #rrggbb")),
        None => Ok(None),
    };
    let accent = rgb("accent", &f.accent)?;
    let surface = rgb("surface", &f.surface)?;
    let logo: Vec<String> = f
        .logo
        .as_deref()
        .unwrap_or_default()
        .trim_end()
        .lines()
        .map(|l| l.trim_end().to_string())
        .collect();
    if logo.iter().all(|l| l.trim().is_empty()) && f.logo.is_some() {
        return Err(format!("{PRODUCT}: logo: blank"));
    }
    let status = match f.status {
        Some(s) => Some(status(s, functions).map_err(|e| format!("{PRODUCT}: status: {e}"))?),
        None => None,
    };
    let shared = actions(f.actions, PRODUCT, functions)?;
    if let Some(slot) = &f.console_accent
        && !SLOTS.contains(&slot.as_str())
    {
        return Err(format!(
            "{PRODUCT}: console-accent: {slot:?} is not one of {}",
            SLOTS.join(", ")
        ));
    }
    // A console takes only its first eight colors as background.
    if let Some(slot) = &f.console_surface
        && !SLOTS[..7].contains(&slot.as_str())
    {
        return Err(format!(
            "{PRODUCT}: console-surface: {slot:?} is not one of {}",
            SLOTS[..7].join(", ")
        ));
    }
    let product = Product {
        title: f.title,
        accent,
        console_accent: f.console_accent,
        surface,
        console_surface: f.console_surface,
        logo,
        status,
    };
    Ok((product, shared))
}

fn status(s: StatusFile, functions: &BTreeSet<String>) -> Result<Status, String> {
    Ok(Status {
        check: shell(&s.check, functions).map_err(|e| format!("check: {e}"))?,
        every: Duration::from_secs(s.every.unwrap_or(10).max(1)),
        pass: text::reflow(s.pass.as_deref().unwrap_or_default()),
        fail: text::reflow(s.fail.as_deref().unwrap_or_default()),
    })
}

fn filter(s: &Option<String>) -> Result<Filter, String> {
    match s.as_deref() {
        None | Some("collapsed") => Ok(Filter::Collapsed),
        Some("open") => Ok(Filter::Open),
        Some(other) => Err(format!("filter: {other:?} is not open or collapsed")),
    }
}

fn reflow_opt(s: &Option<String>) -> Option<String> {
    s.as_deref().map(text::reflow).filter(|t| !t.is_empty())
}

fn setting(f: SettingFile, group: &str, functions: &BTreeSet<String>) -> Result<Setting, String> {
    let name = f.name.clone();
    let fail = |e: String| format!("{name}: {e}");
    if !is_name(&f.name) || f.name.contains(|c: char| c.is_ascii_lowercase()) {
        return Err(format!(
            "{:?} is not a variable name: capitals, digits and _",
            f.name
        ));
    }
    if f.name.starts_with(RESERVED) || f.name == DRY_RUN {
        return Err(fail(format!(
            "{RESERVED}* and {DRY_RUN} are reserved for the runtime"
        )));
    }
    let kind = match &f.kind {
        None => {
            return Err(fail(format!(
                "type is required, one of {}",
                Kind::ALL
                    .iter()
                    .map(|(n, _)| *n)
                    .collect::<Vec<_>>()
                    .join(", ")
            )));
        }
        Some(k) => Kind::parse(k).ok_or_else(|| {
            fail(format!(
                "unknown type {k:?}, one of {}",
                Kind::ALL
                    .iter()
                    .map(|(n, _)| *n)
                    .collect::<Vec<_>>()
                    .join(", ")
            ))
        })?,
    };
    let title = f
        .title
        .filter(|t| !t.trim().is_empty())
        .ok_or_else(|| fail("title is required".into()))?;
    let set = [
        ("options", !f.options.is_empty()),
        ("options-from", f.options_from.is_some()),
        ("filter", f.filter.is_some()),
        ("default", f.default.is_some()),
        ("prefill", f.prefill.is_some()),
        ("value-from", f.value_from.is_some()),
        ("pattern", f.pattern.is_some()),
        ("check", f.check.is_some()),
    ];
    for (key, _) in set.iter().filter(|(_, on)| *on) {
        if !kind.takes().contains(key) {
            return Err(fail(format!(
                "a {} takes no {key}, only {}",
                f.kind.as_deref().unwrap_or_default(),
                kind.takes().join(", ")
            )));
        }
    }
    if kind.listed() && f.options.is_empty() && f.options_from.is_none() {
        return Err(fail("a list needs options or options-from".into()));
    }
    if !f.options.is_empty() && f.options_from.is_some() {
        return Err(fail("options and options-from exclude each other".into()));
    }
    if kind.secret() && f.first {
        return Err(fail("a password takes no first".into()));
    }
    if f.filter.is_some() && f.first {
        return Err(fail("a setting with first takes no filter".into()));
    }
    if f.value_from.is_some() && (f.prefill.is_some() || f.first) {
        return Err(fail("value-from takes no prefill or first".into()));
    }
    let pattern = match &f.pattern {
        Some(p) => Some(Regex::new(p).map_err(|e| fail(format!("pattern: {e}")))?),
        None => None,
    };
    let mut when = Vec::new();
    for line in f.when.lines() {
        if !line.trim().is_empty() {
            when.push(Condition::parse(line).map_err(|e| fail(format!("when: {e}")))?);
        }
    }
    Ok(Setting {
        kind,
        title: text::reflow(&title),
        description: text::reflow(f.description.as_deref().unwrap_or_default()),
        group: text::reflow(group),
        required: f.required,
        default: f.default.as_ref().map(Scalar::text).unwrap_or_default(),
        options: f.options,
        options_from: opt_shell(&f.options_from, "options-from", functions).map_err(fail)?,
        value_from: opt_shell(&f.value_from, "value-from", functions).map_err(fail)?,
        prefill: opt_shell(&f.prefill, "prefill", functions).map_err(fail)?,
        apply: opt_shell(&f.apply, "apply", functions).map_err(fail)?,
        check: opt_shell(&f.check, "check", functions).map_err(fail)?,
        first: f.first,
        filter: filter(&f.filter).map_err(fail)?,
        pattern,
        error: reflow_opt(&f.error),
        when,
        name: f.name,
    })
}

/// Exit statuses 1 to 125. Bash takes the rest for commands it cannot run or find and for
/// signals.
fn errors(e: &BTreeMap<i32, String>, names: &[String]) -> Result<BTreeMap<i32, String>, String> {
    let mut out = BTreeMap::new();
    for (code, text) in e {
        if !(1..=125).contains(code) {
            return Err(format!("errors: {code}: not a status from 1 to 125"));
        }
        let text = text::reflow(text);
        if text.is_empty() {
            return Err(format!("errors: {code}: empty"));
        }
        placeholders(&format!("errors: {code}"), &text, names)?;
        out.insert(*code, text);
    }
    Ok(out)
}

/// Refuses a `{{NAME}}` that names no variable of the module or a password, which would show on
/// screen and in the log.
fn placeholders(key: &str, text: &str, names: &[String]) -> Result<(), String> {
    for name in text::names(text) {
        if !names.contains(&name) {
            return Err(format!(
                "{key}: {{{{{name}}}}} is not a variable of this module, or a password"
            ));
        }
    }
    Ok(())
}

/// Refuses a condition on an undeclared setting.
fn conditions(conds: &[Condition], names: &[String]) -> Result<(), String> {
    match conds.iter().find(|c| !names.contains(&c.name)) {
        Some(c) => Err(format!("when: no such setting: {}", c.name)),
        None => Ok(()),
    }
}

/// How an action runs, which decides what it may declare.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum How {
    /// Runs unasked to decide whether another is offered. No page.
    Unasked,
    /// Runs unasked before the tasks. Its `error` explains a failure.
    Gating,
    /// Opened from a dashboard row, a preset or an `on:` list.
    Opened,
}

fn module(
    files: &Files,
    id: &str,
    functions: &BTreeSet<String>,
    shared: &[Action],
) -> Result<Module, String> {
    let dir = id;
    let file = format!("{dir}/{MODULE}");
    let f: ModuleFile = yaml(files, &file)?;
    let m = |e: String| format!("{file}: {e}");
    if f.title.trim().is_empty() {
        return Err(m("title is required".into()));
    }

    // Conditions are checked once every name is known, so a setting may depend on a later one.
    let mut settings = Vec::new();
    for (group, list) in f.settings.0 {
        if list.is_empty() {
            return Err(m(format!("settings: {group}: no settings")));
        }
        for s in list {
            let s = setting(s, &group, functions).map_err(m)?;
            if settings.iter().any(|o: &Setting| o.name == s.name) {
                return Err(m(format!("{} is declared twice", s.name)));
            }
            settings.push(s);
        }
    }
    let setting_names: Vec<String> = settings.iter().map(|s| s.name.clone()).collect();
    let stages: Vec<String> = f.stages.0.iter().map(|(s, _)| s.clone()).collect();
    let mut tasks = tasks(files, dir, f.stages, functions)?;

    let own = actions(f.actions, &file, functions)?;
    if let Some(a) = own.iter().find(|a| shared.iter().any(|s| s.id == a.id)) {
        return Err(m(format!(
            "actions: {}: declared in {PRODUCT} already",
            a.id
        )));
    }
    let mut actions: Vec<Action> = shared.iter().cloned().chain(own).collect();
    actions.sort_by(|a, b| a.id.cmp(&b.id));
    let is_shared = |id: &str| shared.iter().any(|s| s.id == id);
    let at = |id: &str| {
        if is_shared(id) {
            format!("{PRODUCT}: actions: {id}, as {dir} runs it")
        } else {
            format!("{file}: actions: {id}")
        }
    };

    let mut presets = Vec::new();
    for p in f.presets {
        let t = format!("presets: {}", p.title);
        if p.title.trim().is_empty() {
            return Err(m("presets: title is required".into()));
        }
        for name in p.values.keys() {
            if !setting_names.contains(name) {
                return Err(m(format!("{t}: no such setting: {name}")));
            }
        }
        if p.action.is_some() && !p.values.is_empty() {
            return Err(m(format!("{t}: values and action exclude each other")));
        }
        presets.push(Preset {
            title: text::reflow(&p.title),
            description: text::reflow(p.description.as_deref().unwrap_or_default()),
            values: p
                .values
                .iter()
                .map(|(k, v)| (k.clone(), v.text()))
                .collect(),
            action: p.action,
        });
    }

    // How each action runs, the strictest place first. An unnamed own action is refused, an
    // unnamed product action is dropped.
    let dashboard = dashboard(&f.dashboard).map_err(m)?;
    if let Some(group) = &f.language
        && !settings.iter().any(|s| s.group == *group)
    {
        return Err(m(format!("language: no setting in group {group}")));
    }
    let on = On {
        leave: f.on.leave,
        failure: f.on.failure,
        success: f.on.success,
    };
    let mut how: BTreeMap<String, How> = BTreeMap::new();
    let mut queue: Vec<String> = Vec::new();
    let place = |where_: &str,
                 key: &str,
                 list: &[String],
                 h: How,
                 how: &mut BTreeMap<String, How>,
                 queue: &mut Vec<String>|
     -> Result<(), String> {
        for name in list {
            if !actions.iter().any(|a| a.id == *name) {
                return Err(format!("{where_}: {key}: no such action: {name}"));
            }
            let seen = how.contains_key(name);
            let was = how.get(name).copied().unwrap_or(How::Unasked);
            how.insert(name.clone(), if seen { was.max(h) } else { h });
            if !seen {
                queue.push(name.clone());
            }
        }
        Ok(())
    };
    place(
        &file,
        "requires",
        &f.requires,
        How::Gating,
        &mut how,
        &mut queue,
    )?;
    let listed: Vec<String> = dashboard
        .iter()
        .filter_map(|e| match e {
            Entry::Action(name) => Some(name.clone()),
            _ => None,
        })
        .collect();
    place(
        &file,
        "dashboard",
        &listed,
        How::Opened,
        &mut how,
        &mut queue,
    )?;
    place(
        &file,
        "on: leave",
        &on.leave,
        How::Opened,
        &mut how,
        &mut queue,
    )?;
    place(
        &file,
        "on: failure",
        &on.failure,
        How::Opened,
        &mut how,
        &mut queue,
    )?;
    place(
        &file,
        "on: success",
        &on.success,
        How::Opened,
        &mut how,
        &mut queue,
    )?;
    for p in &presets {
        if let Some(a) = &p.action {
            place(
                &file,
                &format!("presets: {}", p.title),
                std::slice::from_ref(a),
                How::Opened,
                &mut how,
                &mut queue,
            )?;
        }
    }
    while let Some(name) = queue.pop() {
        let a = actions.iter().find(|a| a.id == name).unwrap();
        let (requires, on_failure) = (a.requires.clone(), a.on_failure.clone());
        let where_ = at(&name);
        place(
            &where_,
            "requires",
            &requires,
            How::Unasked,
            &mut how,
            &mut queue,
        )?;
        place(
            &where_,
            "on: failure",
            &on_failure,
            How::Opened,
            &mut how,
            &mut queue,
        )?;
    }
    actions.retain(|a| how.contains_key(&a.id) || !is_shared(&a.id));
    if let Some(a) = actions.iter().find(|a| !how.contains_key(&a.id)) {
        return Err(format!(
            "{}: not named under requires or on: in {MODULE} or another action",
            at(&a.id)
        ));
    }

    // Every name a script may get, to check placeholders and conditions against.
    let mut names = setting_names.clone();
    for t in &tasks {
        if let Some(a) = &t.asks {
            if names.contains(&a.name) {
                return Err(m(format!(
                    "stages: {}: {}: asks: {} is a setting already",
                    t.stage, t.id, a.name
                )));
            }
            names.push(a.name.clone());
        }
    }
    for a in &actions {
        let at = at(&a.id);
        for s in &a.inputs {
            if names.contains(&s.name) {
                return Err(format!("{at}: inputs: {} is declared already", s.name));
            }
            names.push(s.name.clone());
        }
        if let Some(q) = &a.qr {
            if !is_name(q) || q.contains(|c: char| c.is_ascii_lowercase()) {
                return Err(format!("{at}: qr: {q:?} is not a variable name"));
            }
            if names.contains(q) {
                return Err(format!("{at}: qr: {q} is declared already"));
            }
            names.push(q.clone());
        }
    }

    // What a placeholder may show: every name but the passwords.
    let secrets: Vec<&String> = settings
        .iter()
        .chain(actions.iter().flat_map(|a| &a.inputs))
        .filter(|s| s.kind.secret())
        .map(|s| &s.name)
        .collect();
    let shown: Vec<String> = names
        .iter()
        .filter(|n| !secrets.contains(n))
        .cloned()
        .collect();

    // Conditions and placeholders, now that every name is known.
    for s in &settings {
        conditions(&s.when, &setting_names).map_err(|e| m(format!("{}: {e}", s.name)))?;
    }
    for t in &mut tasks {
        let at = format!("{file}: stages: {}: {}", t.stage, t.id);
        conditions(&t.when, &setting_names).map_err(|e| format!("{at}: {e}"))?;
        if let Some(name) = t.texts.keys().find(|n| names.contains(n)) {
            return Err(format!("{at}: texts: {name} is a setting"));
        }
        if let Some(c) = &t.confirm {
            placeholders("confirm", c, &shown).map_err(|e| format!("{at}: {e}"))?;
        }
        if let Some(r) = &t.report {
            placeholders("report", r, &shown).map_err(|e| format!("{at}: {e}"))?;
        }
        t.errors = errors(&t.errors, &shown).map_err(|e| format!("{at}: {e}"))?;
    }
    for a in &mut actions {
        let at = at(&a.id);
        for s in &a.inputs {
            conditions(&s.when, &names).map_err(|e| format!("{at}: {}: {e}", s.name))?;
        }
        for (key, text) in [
            ("error", &a.error),
            ("confirm", &a.confirm),
            ("report", &a.report),
        ] {
            if let Some(t) = text {
                placeholders(key, t, &shown).map_err(|e| format!("{at}: {e}"))?;
            }
        }
        a.errors = errors(&a.errors, &shown).map_err(|e| format!("{at}: {e}"))?;
    }
    let confirm = reflow_opt(&f.confirm);
    if let Some(c) = &confirm {
        placeholders("confirm", c, &shown).map_err(m)?;
    }
    let report = reflow_opt(&f.report);
    if let Some(r) = &report {
        placeholders("report", r, &shown).map_err(m)?;
    }
    let module_errors = errors(&f.errors, &shown).map_err(m)?;

    // What each action may declare, by how it runs.
    for a in &actions {
        let at = at(&a.id);
        let h = how[&a.id];
        let pages = !a.inputs.is_empty() || a.report.is_some();
        if a.tty && (pages || a.confirm.is_some()) {
            return Err(format!("{at}: tty takes no inputs, report or confirm"));
        }
        if a.tty && !a.errors.is_empty() {
            return Err(format!("{at}: tty takes no errors"));
        }
        if h != How::Opened && (pages || a.tty || a.confirm.is_some() || !a.errors.is_empty()) {
            return Err(format!(
                "{at}: an action under requires has no page, tty, confirm or errors"
            ));
        }
        if h == How::Gating && a.error.is_none() {
            return Err(format!(
                "{at}: error is required for an action under the module's requires"
            ));
        }
        if a.on_failure.contains(&a.id) {
            return Err(format!("{at}: on: failure: names the action itself"));
        }
        if a.qr.is_some() && a.report.is_none() {
            return Err(format!("{at}: qr: needs a report"));
        }
        if a.group.is_some() && !listed.contains(&a.id) {
            return Err(format!("{at}: group: not a dashboard row"));
        }
    }
    for name in &on.leave {
        let a = actions.iter().find(|a| a.id == *name).unwrap();
        if !a.inputs.is_empty() || a.confirm.is_some() {
            return Err(m(format!("on: leave: {name} takes no inputs or confirm")));
        }
    }
    if let Some(ring) = ring(&actions) {
        return Err(m(format!("actions that wait on each other: {ring}")));
    }

    let title = text::reflow(&f.title);
    Ok(Module {
        id: id.to_string(),
        start: text::reflow(f.start.as_deref().unwrap_or("Start")),
        title,
        confirm,
        report,
        requires: f.requires,
        dashboard,
        language: f.language,
        on,
        errors: module_errors,
        stages,
        presets,
        settings,
        tasks,
        actions,
    })
}

/// Each name once, `start` and `settings` required.
fn dashboard(names: &[String]) -> Result<Vec<Entry>, String> {
    let mut out = Vec::new();
    for (i, name) in names.iter().enumerate() {
        if names[..i].contains(name) {
            return Err(format!("dashboard: {name} is listed twice"));
        }
        out.push(
            ENTRIES
                .iter()
                .find(|(n, _)| n == name)
                .map(|(_, e)| e.clone())
                .unwrap_or_else(|| Entry::Action(name.clone())),
        );
    }
    for name in ["start", "settings"] {
        if !names.iter().any(|n| n == name) {
            return Err(format!("dashboard: {name} is missing"));
        }
    }
    Ok(out)
}

/// The first cycle through `requires` and `on: failure`, in walk order.
fn ring(actions: &[Action]) -> Option<String> {
    fn walk<'a>(
        actions: &'a [Action],
        name: &'a str,
        path: &mut Vec<&'a str>,
        done: &mut BTreeSet<&'a str>,
    ) -> Option<String> {
        if let Some(i) = path.iter().position(|p| *p == name) {
            let mut ring: Vec<&str> = path[i..].to_vec();
            ring.push(name);
            return Some(ring.join(" → "));
        }
        if done.contains(name) {
            return None;
        }
        path.push(name);
        let a = actions.iter().find(|a| a.id == name)?;
        for next in a.requires.iter().chain(&a.on_failure) {
            if let Some(r) = walk(actions, next, path, done) {
                return Some(r);
            }
        }
        path.pop();
        done.insert(name);
        None
    }
    let mut done = BTreeSet::new();
    actions
        .iter()
        .find_map(|a| walk(actions, &a.id, &mut Vec::new(), &mut done))
}

/// Tasks under `stages:` in run order, each with a `tasks/<task>/task.sh`.
fn tasks(
    files: &Files,
    dir: &str,
    stages: Ordered<Ordered<TaskFile>>,
    functions: &BTreeSet<String>,
) -> Result<Vec<Task>, String> {
    let file = format!("{dir}/{MODULE}");
    let base = format!("{dir}/tasks/");
    if stages.0.is_empty() {
        return Err(format!("{file}: stages: at least one"));
    }
    let mut by_stage: Vec<(String, Vec<Task>)> = Vec::new();
    for (stage, group) in stages.0 {
        if group.0.is_empty() {
            return Err(format!("{file}: stages: {stage}: no tasks"));
        }
        let mut list: Vec<Task> = Vec::new();
        for (id, f) in group.0 {
            let at = format!("{file}: stages: {stage}: {id}");
            if by_stage
                .iter()
                .flat_map(|(_, l)| l)
                .chain(&list)
                .any(|t| t.id == id)
            {
                return Err(format!("{at}: declared twice"));
            }
            let tdir = format!("{base}{id}");
            if !files.has(&format!("{tdir}/task.sh")) {
                return Err(format!("{tdir}: no task.sh"));
            }
            if f.title.trim().is_empty() {
                return Err(format!("{at}: title is required"));
            }
            if !f.yes_after.is_empty() && f.confirm.is_none() {
                return Err(format!("{at}: yes-after without confirm"));
            }
            let asks = match f.asks {
                Some(a) => {
                    let name = a.name.clone();
                    if !is_name(&name)
                        || name.contains(|c: char| c.is_ascii_lowercase())
                        || name.starts_with(RESERVED)
                        || name == DRY_RUN
                    {
                        return Err(format!("{at}: asks: {name:?} is not a variable name"));
                    }
                    if a.options.is_empty() && a.options_from.is_none() {
                        return Err(format!("{at}: asks: needs options or options-from"));
                    }
                    Some(Ask {
                        title: text::reflow(&a.title),
                        description: text::reflow(a.description.as_deref().unwrap_or_default()),
                        filter: filter(&a.filter).map_err(|e| format!("{at}: asks: {e}"))?,
                        options: a.options,
                        options_from: opt_shell(&a.options_from, "options-from", functions)
                            .map_err(|e| format!("{at}: asks: {e}"))?,
                        name,
                    })
                }
                None => None,
            };
            let mut texts = BTreeMap::new();
            for (name, text) in f.texts {
                if !is_name(&name)
                    || name.contains(|c: char| c.is_ascii_lowercase())
                    || name.starts_with(RESERVED)
                    || name == DRY_RUN
                {
                    return Err(format!("{at}: texts: {name:?} is not a variable name"));
                }
                texts.insert(name, text::reflow(&text));
            }
            // Only parsed here. The module checks the names.
            let mut when = Vec::new();
            for line in f.when.lines() {
                if !line.trim().is_empty() {
                    when.push(Condition::parse(line).map_err(|e| format!("{at}: when: {e}"))?);
                }
            }
            list.push(Task {
                id,
                stage: stage.clone(),
                test: files.has(&format!("{tdir}/test.sh")),
                dir: tdir,
                title: text::reflow(&f.title),
                needs: f.needs,
                when,
                asks,
                confirm: reflow_opt(&f.confirm),
                yes_after: f.yes_after,
                report: reflow_opt(&f.report),
                progress: f.progress,
                simulates: f.simulates,
                allow_failure: f.allow_failure,
                errors: f.errors,
                texts,
            });
        }
        by_stage.push((stage, list));
    }
    // A folder without a task never runs.
    if let Some(loose) = files.loose(&base) {
        return Err(format!("{base}{loose}: not in tasks/<task>/"));
    }
    for found in files.dirs(&base) {
        if !by_stage.iter().flat_map(|(_, l)| l).any(|t| t.id == found) {
            return Err(format!(
                "{base}{found}: no such task under stages: in {MODULE}"
            ));
        }
    }
    // `needs` stays within a stage, the stages order the rest.
    let mut out = Vec::new();
    for (stage, group) in &by_stage {
        for t in group {
            let at = format!("{file}: stages: {stage}: {}", t.id);
            for n in &t.needs {
                if n == &t.id {
                    return Err(format!("{at}: needs itself"));
                }
                if !group.iter().any(|o| o.id == *n) {
                    let elsewhere = by_stage.iter().flat_map(|(_, l)| l).find(|o| o.id == *n);
                    return Err(match elsewhere {
                        Some(o) => format!(
                            "{at}: needs {n}, which is in {}: needs stays within a stage",
                            o.stage
                        ),
                        None => format!("{at}: needs: no such task: {n}"),
                    });
                }
            }
        }
        let names: Vec<(String, Vec<String>)> = group
            .iter()
            .map(|t| (t.id.clone(), t.needs.clone()))
            .collect();
        let ordered = order::order(&names).map_err(|e| format!("{file}: stages: {stage}: {e}"))?;
        out.extend(ordered.into_iter().map(|i| group[i].clone()));
    }
    for (i, t) in out.iter().enumerate() {
        let at = format!("{file}: stages: {}: {}", t.stage, t.id);
        for name in &t.yes_after {
            match out.iter().position(|o| o.id == *name) {
                None => return Err(format!("{at}: yes-after: no such task: {name}")),
                Some(j) if j >= i => {
                    return Err(format!("{at}: yes-after: {name} does not run before it"));
                }
                _ => {}
            }
        }
    }
    Ok(out)
}

fn actions(
    map: BTreeMap<String, ActionFile>,
    file: &str,
    functions: &BTreeSet<String>,
) -> Result<Vec<Action>, String> {
    let mut out = Vec::new();
    for (id, f) in map {
        let at = format!("{file}: actions: {id}");
        if ENTRIES.iter().any(|(n, _)| *n == id) {
            return Err(format!("{at}: reserved for a dashboard row"));
        }
        if f.title.trim().is_empty() {
            return Err(format!("{at}: title is required"));
        }
        let run = shell(&f.run, functions).map_err(|e| format!("{at}: run: {e}"))?;
        let mut inputs = Vec::new();
        for s in f.inputs {
            let name = s.name.clone();
            if s.first || s.value_from.is_some() {
                return Err(format!(
                    "{at}: {name}: an input takes no first or value-from"
                ));
            }
            let s = setting(s, "", functions).map_err(|e| format!("{at}: {e}"))?;
            if inputs.iter().any(|o: &Setting| o.name == s.name) {
                return Err(format!("{at}: {} is declared twice", s.name));
            }
            inputs.push(s);
        }
        out.push(Action {
            id,
            run,
            title: text::reflow(&f.title),
            description: text::reflow(f.description.as_deref().unwrap_or_default()),
            group: f.group,
            error: reflow_opt(&f.error),
            requires: f.requires,
            on_failure: f.on.failure,
            inputs,
            confirm: reflow_opt(&f.confirm),
            report: reflow_opt(&f.report),
            qr: f.qr,
            tty: f.tty,
            simulates: f.simulates,
            errors: f.errors,
        });
    }
    Ok(out)
}

#[cfg(test)]
pub mod tests {
    use super::*;

    /// The fixture's module: two stages, a question, a gate and a way out.
    const SETUP: &str = "title: Setup\nstart: Install now\nconfirm: |\n  Install on {{TUX_DISK}}?\n\n  Everything on it is erased.\nreport: |\n  Set up\n\n  {{TUX_HOST}} boots.\nrequires: [root]\ndashboard: [start, note, settings, reset, net]\nlanguage: Region\non:\n  leave: [restart]\n  failure: [share]\n  success: [shell]\nerrors:\n  3: |\n    No internet\n\n    Connect and start again.\nactions:\n  root:\n    title: Running as root\n    error: This has to run as root.\n    run: is_root()\n  note:\n    title: Leave a note\n    description: Writes a note.\n    group: Extras\n    run: note()\n    inputs:\n      - name: TUX_NOTE\n        type: text\n        title: Note\n        required: true\n    report: |\n      Noted\n\n      {{TUX_NOTE}} is written down.\n  net:\n    title: Join a network\n    description: Joins one.\n    group: Network\n    run: join()\n    requires: [root]\n  share:\n    title: Share the log\n    description: Puts the log online.\n    run: share()\n    report: |\n      Shared\n    qr: TUX_URL\n    simulates: true\nstages:\n  prepare:\n    disk:\n      title: Prepare the disk\n      errors:\n        10: |\n          The disk is gone\n\n          {{TUX_DISK}} is not there.\n  install:\n    base:\n      title: Install the base\n      needs: [snapshot]\n      texts:\n        TUX_MOTD: Welcome aboard\n      report: |\n        Installed\n\n        {{TUX_HOST}} is ready.\n      errors:\n        10: |\n          The name is taken\n\n          {{TUX_HOST}} is on the network already.\n    desktop:\n      title: Install the desktop\n      needs: [base]\n      when: TUX_DESKTOP != none\n      allow-failure: true\n    snapshot:\n      title: Go back to a snapshot\n      asks:\n        name: TUX_SNAPSHOT\n        title: Snapshot\n        options-from: options_snapshots()\n      confirm: |\n        Put {{TUX_SNAPSHOT}} in place?\npresets:\n  - title: Desktop\n    description: A desktop.\n    values:\n      TUX_DESKTOP: gnome\n  - title: Core\n    values:\n      TUX_DESKTOP: none\nsettings:\n  Region:\n    - name: TUX_KEYMAP\n      type: list\n      title: Keyboard\n      required: true\n      first: true\n      options: [us, de]\n      apply: apply_keymap()\n  System:\n    - name: TUX_HOST\n      type: text\n      title: Hostname\n      description: What the machine calls itself.\n      required: true\n      prefill: prefill_host()\n      pattern: '^[a-z][a-z0-9-]*$'\n      error: Lower case letters, digits and - only.\n    - name: TUX_DESKTOP\n      type: list\n      title: Desktop\n      required: true\n      options: [gnome, none]\n    - name: TUX_DRIVER\n      type: list\n      title: Driver\n      required: true\n      options: [free, none]\n      when: TUX_DESKTOP != none\n    - name: TUX_PASSWORD\n      type: new-password\n      title: Password\n      required: true\n    - name: TUX_VM\n      type: bool\n      title: Virtual machine\n      value-from: value_vm()\n  Storage:\n    - name: TUX_DISK\n      type: list\n      title: Disk\n      required: true\n      options-from: options_disks()\n      pattern: '^sd'\n    - name: TUX_ENCRYPT\n      type: bool\n      title: Encryption\n      default: true\n";

    /// One module and two product actions it names.
    pub fn fixture() -> Vec<(&'static str, &'static [u8])> {
        vec![
            ("product.yaml", b"title: Tux\naccent: \"#8fbcbb\"\nconsole-accent: cyan\nlogo: |\n  Tux\n\n  ####\nstatus:\n  check: check_online()\n  pass: Online\n  fail: Offline\nactions:\n  restart:\n    title: Restart\n    description: Starts the machine again.\n    run: restart()\n  shell:\n    title: Open a shell\n    description: Until exit.\n    run: open_shell()\n    tty: true\n"),
            ("lib.sh", b"check_online() { true; }\nbroken() {\n    false\n}\nundecided() {\n    [ a = b ] && echo never\n}\noptions_disks() { printf 'sda\\tsda 20G\\nsdb\\tsdb 40G\\n'; }\nprefill_host() { echo tuxbox; }\nvalue_vm() { echo false; }\napply_keymap() { true; }\noptions_snapshots() { echo one; echo two; }\nis_root() { [ \"$(id -u)\" -eq 0 ]; }\nnote() { echo \"$TUX_NOTE\"; }\njoin() { true; }\nrestart() { : >\"${MODULE_CONF%/*}/restarted\"; }\nshare() { printf \"TUX_URL='https://x/1'\\n\" >>\"$MODULE_CONF\"; }\nopen_shell() { true; }\n"),
            ("setup/module.yaml", SETUP.as_bytes()),
            ("setup/tasks/disk/task.sh", b"echo \"$TUX_DISK\" >\"${MODULE_CONF%/*}/disk\"\n[ \"$TUX_HOST\" != slow ] || { trap 'echo asked >\"${MODULE_CONF%/*}/stopped\"' TERM; sleep 30 & wait; }\n"),
            ("setup/tasks/disk/test.sh", b"[ -f \"${MODULE_CONF%/*}/disk\" ]\n"),
            ("setup/tasks/base/task.sh", b"[ \"$TUX_HOST\" != taken ] || exit 10\n[ \"$TUX_HOST\" != broken ] || false\necho \"$TUX_HOST\" >\"${MODULE_CONF%/*}/host\"\necho \"$TUX_MOTD\" >\"${MODULE_CONF%/*}/motd\"\n"),
            ("setup/tasks/desktop/task.sh", b"[ \"$TUX_DRIVER\" = free ]\n"),
            ("setup/tasks/snapshot/task.sh", b"echo \"$TUX_SNAPSHOT\"\n"),
            ("locales/de.po", b"msgid \"\"\nmsgstr \"\"\n\nmsgid \"English\"\nmsgstr \"Deutsch\"\n\nmsgid \"Hostname\"\nmsgstr \"Rechnername\"\n"),
        ]
    }

    /// The fixture with one file replaced, or added.
    fn with(path: &'static str, body: &'static str) -> Vec<(&'static str, &'static [u8])> {
        let mut files: Vec<(&str, &[u8])> =
            fixture().into_iter().filter(|(f, _)| *f != path).collect();
        files.push((path, body.as_bytes()));
        files
    }

    /// The fixture with `old` in its module.yaml written as `new`.
    fn edited(old: &str, new: &str) -> Vec<(&'static str, &'static [u8])> {
        assert!(SETUP.contains(old), "{old:?}");
        with("setup/module.yaml", leak(SETUP.replacen(old, new, 1)))
    }

    fn leak(s: String) -> &'static str {
        Box::leak(s.into_boxed_str())
    }

    /// The rest of a `tiny` module.yaml: three actions that name nothing and one task.
    const TINY: &str = "actions:\n  root:\n    title: Root\n    error: No\n    run: fn_a()\n  row:\n    title: Row\n    run: fn_a()\n  asks:\n    title: Asks\n    run: fn_a()\n    inputs:\n      - name: A_IN\n        type: text\n        title: In\nstages:\n  a:\n    one:\n      title: One\n";

    /// One module, `head` then `TINY` as its module.yaml.
    fn tiny(head: &str) -> Vec<(&'static str, &'static [u8])> {
        tiny_with(head, TINY)
    }

    /// One module, `head` then `rest` as its module.yaml.
    fn tiny_with(head: &str, rest: &str) -> Vec<(&'static str, &'static [u8])> {
        vec![
            ("product.yaml", b"title: Tux\n"),
            ("lib.sh", b"fn_a() { true; }\n"),
            ("m/module.yaml", leak(format!("{head}{rest}")).as_bytes()),
            ("m/tasks/one/task.sh", b"true\n"),
        ]
    }

    fn refused(files: &[(&str, &[u8])], says: &str) {
        let err = load(files)
            .err()
            .unwrap_or_else(|| panic!("loaded, wanted {says:?}"));
        assert!(err.contains(says), "{err:?} does not say {says:?}");
    }

    /// A placeholder shows its value on screen and in the log.
    #[test]
    fn no_placeholder_names_a_password() {
        refused(
            &edited("Install on {{TUX_DISK}}?", "Install on {{TUX_PASSWORD}}?"),
            "{{TUX_PASSWORD}} is not a variable of this module, or a password",
        );
    }

    #[test]
    fn the_fixture_loads_in_order() {
        let l = load(&fixture()).unwrap();
        assert_eq!(l.product.title, "Tux");
        assert_eq!(l.product.accent, Some(Rgb(0x8f, 0xbc, 0xbb)));
        assert_eq!(l.product.logo, ["Tux", "", "####"]);
        let m = l.module("setup").unwrap();
        let order: Vec<&str> = m.tasks.iter().map(|t| t.id.as_str()).collect();
        assert_eq!(order, ["disk", "snapshot", "base", "desktop"]);
        assert_eq!(m.stages, ["prepare", "install"]);
        assert_eq!(m.tasks[0].dir, "setup/tasks/disk");
        assert_eq!(
            m.tasks[0].errors[&10],
            "The disk is gone\n\n{{TUX_DISK}} is not there."
        );
        assert!(m.tasks[0].test && !m.tasks[1].test);
        assert_eq!(
            m.confirm.as_deref(),
            Some("Install on {{TUX_DISK}}?\n\nEverything on it is erased.")
        );
        assert_eq!(m.report.as_deref(), Some("Set up\n\n{{TUX_HOST}} boots."));
        assert_eq!(
            m.setting("TUX_DRIVER").unwrap().when[0].to_string(),
            "TUX_DESKTOP != none"
        );
        assert_eq!(m.setting("TUX_KEYMAP").unwrap().filter(), Filter::Open);
        assert_eq!(
            m.tasks[1].asks.as_ref().unwrap().options_from,
            Some(Shell::Call("options_snapshots".into()))
        );
        let ids: Vec<&str> = m.actions.iter().map(|a| a.id.as_str()).collect();
        assert_eq!(ids, ["net", "note", "restart", "root", "share", "shell"]);
        assert_eq!(
            m.action("restart").unwrap().run,
            Shell::Call("restart".into())
        );
        assert!(m.declared().contains(&"TUX_URL") && m.declared().contains(&"TUX_NOTE"));
        assert!(m.texts().contains(&"Install now".to_string()));
        assert!(m.texts().contains(&"Open a shell".to_string()));
        assert!(
            m.texts()
                .contains(&"Set up\n\n{{TUX_HOST}} boots.".to_string())
        );
        assert_eq!(
            m.dashboard,
            [
                Entry::Start,
                Entry::Action("note".into()),
                Entry::Settings,
                Entry::Reset,
                Entry::Action("net".into())
            ]
        );
        assert_eq!(m.language.as_deref(), Some("Region"));
        assert_eq!(l.texts()[..2], ["Online", "Offline"]);
    }

    #[test]
    fn refuses_what_cannot_run() {
        const OK: &str =
            "title: M\nrequires: [root]\ndashboard: [start, settings, asks]\non:\n  leave: [row]\n";
        assert!(load(&tiny(OK)).is_ok());
        for (module, says) in [
            (
                "title: M\nrequires: [root]\ndashboard: [start, settings, asks, asks]\non:\n  leave: [row]\n",
                "asks is listed twice",
            ),
            (
                "title: M\nrequires: [root]\ndashboard: [settings, asks]\non:\n  leave: [row]\n",
                "start is missing",
            ),
            (
                "title: M\nrequires: [root]\ndashboard: [start, asks]\non:\n  leave: [row]\n",
                "settings is missing",
            ),
            (
                "title: M\nrequires: [root]\ndashboard: [start, settings, asks, nope]\non:\n  leave: [row]\n",
                "dashboard: no such action: nope",
            ),
            ("title: M\nrequires: [root]\n", "missing field `dashboard`"),
            (
                "title: M\nrequires: [root]\ndashboard: [start, settings, asks]\nlanguage: Nope\non:\n  leave: [row]\n",
                "language: no setting in group Nope",
            ),
            (
                "title: M\nrequires: [root]\ndashboard: [start, settings, asks, row]\nsettings:\n  System:\n    - name: lower\n      type: text\n      title: T\n",
                "not a variable name",
            ),
            (
                "title: M\nrequires: [root]\ndashboard: [start, settings, asks, row]\nsettings:\n  System:\n    - name: MODULE_X\n      type: text\n      title: T\n",
                "reserved for the runtime",
            ),
            (
                "title: M\nrequires: [root]\ndashboard: [start, settings, asks, row]\nsettings:\n  System:\n    - name: A\n      type: text\n      title: T\n      options: [x]\n",
                "takes no options",
            ),
            (
                "title: M\nrequires: [root]\ndashboard: [start, settings, asks, row]\nsettings:\n  System:\n    - name: A\n      type: list\n      title: T\n",
                "options or options-from",
            ),
            (
                "title: M\nrequires: [root]\ndashboard: [start, settings, asks, row]\nsettings:\n  System:\n    - name: A\n      type: text\n      title: T\n      prefill: nothing()\n",
                "not a function in lib.sh",
            ),
            (
                "title: M\nrequires: [root]\ndashboard: [start, settings, asks, row]\nsettings:\n  System:\n    - name: A\n      type: text\n      title: T\n      prefill: ./prefill.sh\n",
                "is not written name()",
            ),
            (
                "title: M\nrequires: [root]\ndashboard: [start, settings, asks, row]\nsettings:\n  System:\n    - name: A\n      type: text\n      title: T\n      when: B == 1\n",
                "no such setting: B",
            ),
            (
                "title: M\nrequires: [root]\ndashboard: [start, settings, asks, row]\nerrors:\n  200: Too high\n",
                "from 1 to 125",
            ),
            (
                "title: M\nrequires: [root]\ndashboard: [start, settings, asks, row]\nconfirm: Erase {{NOPE}}?\n",
                "{{NOPE}} is not a variable",
            ),
            (
                "title: M\nrequires: [root]\ndashboard: [start, settings, asks, row]\nreport: Ready on {{NOPE}}\n",
                "{{NOPE}} is not a variable",
            ),
            (
                "title: M\nrequires: [root]\ndashboard: [start, settings, asks, row]\nsettings:\n  System: []\n",
                "settings: System: no settings",
            ),
            (
                "title: M\nrequires: [root]\ndashboard: [start, settings, asks, row]\nsettings:\n  System:\n    - name: A\n      type: text\n      title: T\n      group: X\n",
                "unknown field `group`",
            ),
            (
                "title: M\nrequires: [nope]\ndashboard: [start, settings]\n",
                "no such action: nope",
            ),
            (
                "title: M\ndashboard: [start, settings]\n",
                "m/module.yaml: actions: asks: not named",
            ),
            (
                "title: M\nrequires: [root, asks]\non:\n  leave: [row]\ndashboard: [start, settings]\n",
                "has no page",
            ),
            (
                "title: M\nrequires: [root, row]\ndashboard: [start, settings, asks]\n",
                "error is required",
            ),
            (
                "title: M\nrequires: [root]\ndashboard: [start, settings, row]\non:\n  leave: [asks]\n",
                "asks takes no inputs or confirm",
            ),
        ] {
            refused(&tiny(module), says);
        }
        for (rest, says) in [
            (
                TINY.replace("    title: Row\n", "    title: Row\n    group: Ways\n"),
                "group: not a dashboard row",
            ),
            (
                TINY.replace("  row:\n", "  reset:\n"),
                "m/module.yaml: actions: reset: reserved for a dashboard row",
            ),
            (
                TINY.replace("    run: fn_a()\n  row:", "  row:"),
                "missing field `run`",
            ),
            (
                TINY.replace("stages:\n  a:\n    one:\n      title: One\n", ""),
                "stages: at least one",
            ),
            (
                TINY.replace("    one:\n      title: One\n", "    {}\n"),
                "stages: a: no tasks",
            ),
            (
                format!("{TINY}    two:\n      title: Two\n"),
                "m/tasks/two: no task.sh",
            ),
            (
                format!("{TINY}  b:\n    one:\n      title: One again\n"),
                "stages: b: one: declared twice",
            ),
            (
                format!("{TINY}      texts:\n        lower: x\n"),
                "texts: \"lower\" is not a variable name",
            ),
            (
                format!("{TINY}      texts:\n        A_IN: x\n"),
                "texts: A_IN is a setting",
            ),
        ] {
            refused(&tiny_with(OK, &rest), says);
        }
        let mut files = tiny(OK);
        files.push(("m/tasks/two/task.sh", b"true\n"));
        refused(&files, "m/tasks/two: no such task under stages:");
        let mut files = tiny(OK);
        files.push(("m/tasks/loose.sh", b"true\n"));
        refused(&files, "loose.sh: not in tasks/<task>/");
        refused(
            &edited(
                "    base:\n      title: Install the base\n      needs: [snapshot]\n",
                "    base:\n      title: Install the base\n      needs: [disk]\n",
            ),
            "which is in prepare",
        );
        refused(
            &edited("      needs: [snapshot]\n", "      needs: [desktop]\n"),
            "wait on each other",
        );
        refused(
            &edited(
                "      needs: [snapshot]\n",
                "      needs: [snapshot]\n      yes-after: [disk]\n",
            ),
            "without confirm",
        );
        refused(
            &edited(
                "      needs: [snapshot]\n",
                "      needs: [snapshot]\n      unknown: 1\n",
            ),
            "unknown",
        );
        refused(
            &edited(
                "      title: Prepare the disk\n",
                "      title: Prepare the disk\n      asks:\n        name: TUX_HOST\n        title: H\n        options: [a]\n",
            ),
            "is a setting already",
        );
        refused(
            &edited("    report: |\n      Shared\n", ""),
            "qr: needs a report",
        );
        refused(
            &edited(
                "    error: This has to run as root.\n",
                "    error: This has to run as root.\n    requires: [root]\n",
            ),
            "wait on each other",
        );
        refused(
            &edited(
                "  root:\n",
                "  restart:\n    title: Again\n    run: join()\n  root:\n",
            ),
            "actions: restart: declared in product.yaml already",
        );
        refused(
            &with("product.yaml", "title: X\naccent: red\n"),
            "not #rrggbb",
        );
        refused(
            &with("product.yaml", "title: X\nconsole-accent: pink\n"),
            "console-accent",
        );
        refused(
            &with("product.yaml", "title: X\nstatus:\n  check: nothing()\n"),
            "not a function",
        );
    }

    /// A product action no module names is refused.
    #[test]
    fn a_product_action_is_one_of_the_modules_that_name_it() {
        let product = std::str::from_utf8(fixture()[0].1).unwrap().to_string();
        let spare = leak(format!(
            "{product}  spare:\n    title: Spare\n    run: join()\n"
        ));
        refused(
            &with("product.yaml", spare),
            "product.yaml: actions: spare: not named",
        );
        let mut files = with("product.yaml", spare);
        files.push((
            "other/module.yaml",
            b"title: Other\ndashboard: [start, settings]\non:\n  leave: [spare]\nstages:\n  a:\n    one:\n      title: One\n",
        ));
        files.push(("other/tasks/one/task.sh", b"true\n"));
        let l = load(&files).unwrap();
        assert!(l.module("setup").unwrap().action("spare").is_none());
        let other = l.module("other").unwrap();
        let ids: Vec<&str> = other.actions.iter().map(|a| a.id.as_str()).collect();
        assert_eq!(ids, ["spare"]);
    }

    #[test]
    fn reads_the_functions_of_a_library() {
        let f = functions("a() {\n}\nfunction b {\n}\n  c () { :; }\nnot a definition\n# d() {\n");
        assert_eq!(f.into_iter().collect::<Vec<_>>(), ["a", "b", "c"]);
    }
}

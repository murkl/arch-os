//! What the product and its modules declare, read and checked once. It knows the shape of the
//! yaml, so nothing below it knows anything about the system being installed.
//!
//! A product is `product.yaml` and `lib.sh` beside the modules, each a folder with a
//! `module.yaml`, `tasks/<stage>/<task>/` and `actions/<action>/`. A module that loads is a
//! module that runs: an authoring mistake fails the tests, never a task that silently never fires.

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

/// The names the runtime puts into a script's environment, and so no setting may take.
pub const RESERVED: &str = "MODULE_";
pub const DRY_RUN: &str = "DRY_RUN";
pub const CONF: &str = "MODULE_CONF";
pub const LOG: &str = "MODULE_LOG";
pub const LANGUAGE: &str = "MODULE_LANGUAGE";
pub const VERSION: &str = "MODULE_VERSION";

/// The two answers of a bool, written into the answer file and tested by scripts as they stand.
pub const TRUE: &str = "true";
pub const FALSE: &str = "false";

// ─── The model ───────────────────────────────────────────────────────────────

/// The product: what no module answers for its neighbours.
#[derive(Clone, Debug, PartialEq)]
pub struct Product {
    /// The name over every page. Not translated: it is a name.
    pub title: String,
    pub accent: Option<Rgb>,
    /// The slot of the console's sixteen colours the accent takes there, by name: the console
    /// shows slots, painted by whoever dressed it.
    pub console_accent: Option<String>,
    /// Behind the row under the cursor, and its slot on the console.
    pub surface: Option<Rgb>,
    pub console_surface: Option<String>,
    /// The wordmark, line by line. Everything above the first blank line is the eyebrow.
    pub logo: Vec<String>,
    pub status: Option<Status>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rgb(pub u8, pub u8, pub u8);

/// One thing about the machine the header watches: shell whose exit status is the answer.
#[derive(Clone, Debug, PartialEq)]
pub struct Status {
    pub check: Shell,
    pub every: Duration,
    pub pass: String,
    pub fail: String,
}

/// Shell a declaration names: a function of lib.sh written `name()`, or a file beside the yaml
/// written `./name.sh`, held as its path in the product.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Shell {
    Call(String),
    File(String),
}

#[derive(Clone, Debug, PartialEq)]
pub struct Module {
    /// The folder, which opens it from the command line and names its answers and log.
    pub id: String,
    pub title: String,
    /// The dashboard's first row, which starts the work.
    pub start: String,
    /// Asked after every password and before the work: the question, then what happens.
    pub confirm: Option<String>,
    /// Actions that have to say yes before the work. The first no stands a page in front.
    pub requires: Vec<String>,
    pub on: On,
    /// What any of its scripts means by stopping itself with a status, the headline first.
    pub errors: BTreeMap<i32, String>,
    pub stages: Vec<String>,
    pub presets: Vec<Preset>,
    pub settings: Vec<Setting>,
    /// In the order they run: by stage, and inside a stage by `needs`.
    pub tasks: Vec<Task>,
    pub actions: Vec<Action>,
}

/// Where a module offers its actions: each a list of their names, in order.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct On {
    pub dashboard: Vec<String>,
    pub leave: Vec<String>,
    pub failure: Vec<String>,
    pub success: Vec<String>,
}

/// A starting point, offered once on a machine that has answered nothing: a set of answers, or
/// the action that fetches them.
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

    /// The keys only some kinds take. One on a kind that does not is refused: nothing reads it.
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

    /// Chosen from a list.
    pub fn listed(self) -> bool {
        matches!(self, Kind::List | Kind::OpenList)
    }

    /// Never written down: asked right before the run that needs it, used and forgotten.
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

/// One thing a module needs to know, and everything about what a valid answer looks like. The
/// same rules hold when asking and when reading back an answer file somebody edited by hand.
#[derive(Clone, Debug)]
pub struct Setting {
    pub name: String,
    pub kind: Kind,
    pub title: String,
    pub description: String,
    /// The heading its row sits under on the dashboard.
    pub group: String,
    pub required: bool,
    pub default: String,
    pub options: Vec<String>,
    pub options_from: Option<Shell>,
    /// Printed instead of asked: read when the module opens and whenever an answer changes,
    /// never shown and never stored.
    pub value_from: Option<Shell>,
    /// Prints a suggestion. Still asked.
    pub prefill: Option<Shell>,
    /// Puts the answer into effect on this machine, such as a keymap, as it is given.
    pub apply: Option<Shell>,
    /// Tries a password on what it opens before it is taken.
    pub check: Option<Shell>,
    /// Asked before everything else, its list's box open, since nothing is known to type on yet.
    pub first: bool,
    pub filter: Filter,
    pub pattern: Option<Regex>,
    /// What a wrong answer is told.
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

    /// Whether the list opens with its box: asked first, nothing is known to type `/` on.
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

    /// Every answer there is, where the declaration writes them out.
    #[allow(dead_code)]
    fn domain(&self) -> Option<Vec<&str>> {
        match self.kind {
            Kind::Bool => Some(vec![TRUE, FALSE]),
            _ if !self.options.is_empty() => {
                Some(self.options.iter().map(String::as_str).collect())
            }
            _ => None,
        }
    }
}

/// A question a task puts mid-run, for a value only known once some work is done. Always a
/// list, never stored, and a list that comes back empty skips the task.
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
    /// The folder, which `needs` and `yes-after` name it by.
    pub id: String,
    pub stage: String,
    /// Its folder in the product: `installer/tasks/prepare/partition`.
    pub dir: String,
    pub title: String,
    pub needs: Vec<String>,
    pub when: Vec<Condition>,
    pub asks: Option<Ask>,
    /// A yes or no before it runs, opening on No. No skips it.
    pub confirm: Option<String>,
    /// Tasks before it: where one ran in this run, `confirm` opens on Yes.
    pub yes_after: Vec<String>,
    /// A page the run stops on afterwards, the first paragraph the headline.
    pub report: Option<String>,
    /// The last line it printed is shown under it while it runs.
    pub progress: bool,
    /// Runs on a dry run too, reading `DRY_RUN` itself.
    pub simulates: bool,
    /// Its failure does not stop the run.
    pub allow_failure: bool,
    pub errors: BTreeMap<i32, String>,
    /// It has a `test.sh`.
    pub test: bool,
}

impl Task {
    pub fn script(&self) -> String {
        format!("{}/task.sh", self.dir)
    }

    pub fn test_script(&self) -> String {
        format!("{}/test.sh", self.dir)
    }

    pub fn applies(&self, get: impl Fn(&str) -> String) -> bool {
        condition::hold_all(&self.when, get)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Action {
    pub id: String,
    pub dir: String,
    pub title: String,
    /// The sentence under its row. Choosing the row is the consent, so it says what leaves.
    pub description: String,
    /// What a no from it means: the page in front of the work, the headline over a failure.
    pub error: Option<String>,
    /// Actions that have to say yes for this one to be offered at all.
    pub requires: Vec<String>,
    /// Opened where this one says no: the first of them this machine offers.
    pub on_failure: Vec<String>,
    /// Its questions before it runs, a page each, kept for this session only.
    pub inputs: Vec<Setting>,
    pub confirm: Option<String>,
    pub report: Option<String>,
    /// An answer its script wrote, drawn on the report as a code to scan.
    pub qr: Option<String>,
    /// Its page is the terminal itself.
    pub tty: bool,
    pub simulates: bool,
    pub errors: BTreeMap<i32, String>,
}

impl Action {
    pub fn script(&self) -> String {
        format!("{}/action.sh", self.dir)
    }
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

    /// The actions a list of names stands for, in its order.
    pub fn named(&self, names: &[String]) -> Vec<&Action> {
        names.iter().filter_map(|n| self.action(n)).collect()
    }

    /// Every variable a script of this module may be handed: its settings, its actions' inputs
    /// and answers, its tasks' questions.
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

    /// What a script of this module means by stopping itself with `code`: the unit's own words,
    /// else the module's. The headline, then the rest.
    pub fn told<'a>(&'a self, own: &'a BTreeMap<i32, String>, code: i32) -> Option<&'a str> {
        own.get(&code)
            .or_else(|| self.errors.get(&code))
            .map(String::as_str)
    }

    /// Whether leaving asks about the machine: a module with ways out says it booted to run it.
    pub fn leaves(&self) -> bool {
        !self.on.leave.is_empty()
    }

    /// Every sentence this module says, once each, in the order it says them: what a catalog
    /// translates.
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
        }
        for a in &self.actions {
            add(&a.title);
            add(&a.description);
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

/// Everything embedded, loaded.
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

    /// Every sentence of the product and its modules.
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

/// The embedded product, loaded once. A product that does not load fails the tests, so a
/// shipped binary never gets here with one.
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

/// A value read as text whatever shape it was written in: `default: true` is how a person
/// writes one, and every answer ends up in an environment variable.
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

/// `when:` as it may be written: one line, or a list of them.
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
    #[serde(default)]
    requires: Vec<String>,
    #[serde(default)]
    on: OnFile,
    #[serde(default)]
    errors: BTreeMap<i32, String>,
    #[serde(default)]
    stages: Vec<String>,
    #[serde(default)]
    presets: Vec<PresetFile>,
    #[serde(default)]
    settings: Vec<SettingFile>,
}

#[derive(Deserialize, Default)]
#[serde(deny_unknown_fields, rename_all = "kebab-case")]
struct OnFile {
    #[serde(default)]
    dashboard: Vec<String>,
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
    group: Option<String>,
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
    error: Option<String>,
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

/// The embedded files, by path.
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

    /// Whether anything lies directly under `prefix` that is a file rather than a folder.
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

/// Reads every file of a product and checks it over.
pub fn load(files: &[(&str, &[u8])]) -> Result<Loaded, String> {
    let files = Files(files);
    let lib = files.has(LIB);
    let functions = if lib {
        functions(files.text(LIB)?)
    } else {
        BTreeSet::new()
    };
    let product = product(&files, &functions)?;
    let mut modules = Vec::new();
    for id in files.dirs("") {
        if id == "locales" || !files.has(&format!("{id}/{MODULE}")) {
            continue;
        }
        modules.push(module(&files, &id, &functions).map_err(|e| format!("{id}/{e}"))?);
    }
    Ok(Loaded {
        product,
        modules,
        lib,
    })
}

/// Every function lib.sh defines, read rather than run.
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

/// Shell a key names, settled against the folder of its yaml.
fn shell(
    expr: &str,
    dir: &str,
    files: &Files,
    functions: &BTreeSet<String>,
) -> Result<Shell, String> {
    let expr = expr.trim();
    if let Some(name) = expr.strip_suffix("()") {
        if !is_name(name) {
            return Err(format!("{expr:?} is no function name"));
        }
        if !functions.contains(name) {
            return Err(format!("{name}() is not a function in {LIB}"));
        }
        return Ok(Shell::Call(name.to_string()));
    }
    let Some(file) = expr.strip_prefix("./") else {
        return Err(format!(
            "{expr:?} is neither a function of {LIB}, written name(), nor a file beside this yaml, written ./name.sh"
        ));
    };
    if !file.ends_with(".sh") || file.contains('/') {
        return Err(format!(
            "{expr:?}: a file beside this yaml is written ./name.sh"
        ));
    }
    let path = format!("{dir}/{file}");
    if !files.has(&path) {
        return Err(format!("no such script: {expr}"));
    }
    Ok(Shell::File(path))
}

fn opt_shell(
    expr: &Option<String>,
    key: &str,
    dir: &str,
    files: &Files,
    functions: &BTreeSet<String>,
) -> Result<Option<Shell>, String> {
    match expr {
        Some(e) => shell(e, dir, files, functions)
            .map(Some)
            .map_err(|err| format!("{key}: {err}")),
        None => Ok(None),
    }
}

/// The console's colours a product may name, black and white left out: the field and the text.
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

fn product(files: &Files, functions: &BTreeSet<String>) -> Result<Product, String> {
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
        return Err(format!("{PRODUCT}: logo: draws nothing"));
    }
    let status = match f.status {
        Some(s) => {
            Some(status(s, "", files, functions).map_err(|e| format!("{PRODUCT}: status: {e}"))?)
        }
        None => None,
    };
    if let Some(slot) = &f.console_accent
        && !SLOTS.contains(&slot.as_str())
    {
        return Err(format!(
            "{PRODUCT}: console-accent: {slot:?} is one of {}",
            SLOTS.join(", ")
        ));
    }
    // Behind text a console takes only its first eight colours.
    if let Some(slot) = &f.console_surface
        && !SLOTS[..7].contains(&slot.as_str())
    {
        return Err(format!(
            "{PRODUCT}: console-surface: {slot:?} is one of {}",
            SLOTS[..7].join(", ")
        ));
    }
    Ok(Product {
        title: f.title,
        accent,
        console_accent: f.console_accent,
        surface,
        console_surface: f.console_surface,
        logo,
        status,
    })
}

fn status(
    s: StatusFile,
    dir: &str,
    files: &Files,
    functions: &BTreeSet<String>,
) -> Result<Status, String> {
    Ok(Status {
        check: shell(&s.check, dir, files, functions).map_err(|e| format!("check: {e}"))?,
        every: Duration::from_secs(s.every.unwrap_or(10).max(1)),
        pass: text::reflow(s.pass.as_deref().unwrap_or_default()),
        fail: text::reflow(s.fail.as_deref().unwrap_or_default()),
    })
}

fn filter(s: &Option<String>) -> Result<Filter, String> {
    match s.as_deref() {
        None | Some("collapsed") => Ok(Filter::Collapsed),
        Some("open") => Ok(Filter::Open),
        Some(other) => Err(format!("filter: {other:?} is open or collapsed")),
    }
}

fn reflow_opt(s: &Option<String>) -> Option<String> {
    s.as_deref().map(text::reflow).filter(|t| !t.is_empty())
}

/// A setting as written, checked over and its shell settled against `dir`.
fn setting(
    f: SettingFile,
    dir: &str,
    files: &Files,
    functions: &BTreeSet<String>,
) -> Result<Setting, String> {
    let name = f.name.clone();
    let fail = |e: String| format!("{name}: {e}");
    if !is_name(&f.name) || f.name.contains(|c: char| c.is_ascii_lowercase()) {
        return Err(format!(
            "{:?} is no variable name: capitals, digits and _",
            f.name
        ));
    }
    if f.name.starts_with(RESERVED) || f.name == DRY_RUN {
        return Err(fail(format!(
            "{RESERVED}* and {DRY_RUN} belong to the runtime"
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
                "a {} takes no {key}, of the keys a type decides only {}",
                f.kind.as_deref().unwrap_or_default(),
                kind.takes().join(", ")
            )));
        }
    }
    if kind.listed() && f.options.is_empty() && f.options_from.is_none() {
        return Err(fail(
            "a list takes its answers from options or options-from".into(),
        ));
    }
    if !f.options.is_empty() && f.options_from.is_some() {
        return Err(fail(
            "options and options-from are two answers to the same question".into(),
        ));
    }
    if kind.secret() && f.first {
        return Err(fail(
            "a password is asked right before the run, so it cannot be asked first".into(),
        ));
    }
    if f.filter.is_some() && f.first {
        return Err(fail(
            "a question asked first carries its box open by itself".into(),
        ));
    }
    if f.value_from.is_some() && (f.prefill.is_some() || f.first) {
        return Err(fail(
            "value-from settles the value: it is neither suggested nor asked first".into(),
        ));
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
        group: text::reflow(f.group.as_deref().unwrap_or_default()),
        required: f.required,
        default: f.default.as_ref().map(Scalar::text).unwrap_or_default(),
        options: f.options,
        options_from: opt_shell(&f.options_from, "options-from", dir, files, functions)
            .map_err(fail)?,
        value_from: opt_shell(&f.value_from, "value-from", dir, files, functions).map_err(fail)?,
        prefill: opt_shell(&f.prefill, "prefill", dir, files, functions).map_err(fail)?,
        apply: opt_shell(&f.apply, "apply", dir, files, functions).map_err(fail)?,
        check: opt_shell(&f.check, "check", dir, files, functions).map_err(fail)?,
        first: f.first,
        filter: filter(&f.filter).map_err(fail)?,
        pattern,
        error: reflow_opt(&f.error),
        when,
        name: f.name,
    })
}

/// Statuses a script may stop itself with: above 0, below what bash spends on a command it
/// cannot run or find and on signals.
fn errors(e: &BTreeMap<i32, String>, names: &[String]) -> Result<BTreeMap<i32, String>, String> {
    let mut out = BTreeMap::new();
    for (code, text) in e {
        if !(1..=125).contains(code) {
            return Err(format!(
                "errors: {code}: a script chooses a status from 1 to 125, bash spends the rest"
            ));
        }
        let text = text::reflow(text);
        if text.is_empty() {
            return Err(format!("errors: {code}: says nothing"));
        }
        placeholders(&format!("errors: {code}"), &text, names)?;
        out.insert(*code, text);
    }
    Ok(out)
}

/// Refuses a `{{NAME}}` naming no variable of the module: a sentence with a hole in it.
fn placeholders(key: &str, text: &str, names: &[String]) -> Result<(), String> {
    for name in text::names(text) {
        if !names.contains(&name) {
            return Err(format!(
                "{key}: {{{{{name}}}}} is not a variable of this module"
            ));
        }
    }
    Ok(())
}

/// Refuses a condition about a setting nobody declares.
fn conditions(conds: &[Condition], names: &[String]) -> Result<(), String> {
    match conds.iter().find(|c| !names.contains(&c.name)) {
        Some(c) => Err(format!("when: no such setting: {}", c.name)),
        None => Ok(()),
    }
}

/// How an action is run, which decides what it may say.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum How {
    /// Runs by itself to answer whether another is offered: no page.
    Unasked,
    /// Runs by itself in front of the work, and its no is read: it says why.
    Gating,
    /// Somebody opens it: a row, a preset, what another opens on failure.
    Opened,
}

fn module(files: &Files, id: &str, functions: &BTreeSet<String>) -> Result<Module, String> {
    let dir = id;
    let f: ModuleFile = yaml(files, &format!("{dir}/{MODULE}"))?;
    let m = |e: String| format!("{MODULE}: {e}");
    if f.title.trim().is_empty() {
        return Err(m("title is required".into()));
    }
    if f.stages.is_empty() {
        return Err(m("stages: at least one".into()));
    }
    for (i, stage) in f.stages.iter().enumerate() {
        if f.stages[..i].contains(stage) {
            return Err(m(format!("stages: {stage} is listed twice")));
        }
    }

    // The settings, then every condition once every name is known, so one may be guarded by a
    // setting declared after it.
    let mut settings = Vec::new();
    for s in f.settings {
        let s = setting(s, dir, files, functions).map_err(m)?;
        if settings.iter().any(|o: &Setting| o.name == s.name) {
            return Err(m(format!("{} is declared twice", s.name)));
        }
        settings.push(s);
    }
    let mut tasks = tasks(files, dir, &f.stages, functions)?;
    let mut actions = actions(files, dir, functions)?;

    // Every name a script may be handed, so a sentence and a condition can be held to them.
    let mut names: Vec<String> = settings.iter().map(|s| s.name.clone()).collect();
    for t in &tasks {
        if let Some(a) = &t.asks {
            if names.contains(&a.name) {
                return Err(format!(
                    "tasks/{}/{}/task.yaml: asks: {} is a setting already",
                    t.stage, t.id, a.name
                ));
            }
            names.push(a.name.clone());
        }
    }
    for a in &actions {
        let at = format!("actions/{}/action.yaml", a.id);
        for s in &a.inputs {
            if names.contains(&s.name) {
                return Err(format!("{at}: inputs: {} is declared already", s.name));
            }
            names.push(s.name.clone());
        }
        if let Some(q) = &a.qr {
            if !is_name(q) || q.contains(|c: char| c.is_ascii_lowercase()) {
                return Err(format!("{at}: qr: {q:?} is no variable name"));
            }
            if names.contains(q) {
                return Err(format!("{at}: qr: {q} is declared already"));
            }
            names.push(q.clone());
        }
    }
    let setting_names: Vec<String> = settings.iter().map(|s| s.name.clone()).collect();

    // Conditions and sentences, now that every name is known: a setting may be guarded by one
    // declared after it.
    for s in &settings {
        conditions(&s.when, &setting_names).map_err(|e| m(format!("{}: {e}", s.name)))?;
    }
    for t in &mut tasks {
        let at = format!("tasks/{}/{}/task.yaml", t.stage, t.id);
        conditions(&t.when, &setting_names).map_err(|e| format!("{at}: {e}"))?;
        if let Some(c) = &t.confirm {
            placeholders("confirm", c, &names).map_err(|e| format!("{at}: {e}"))?;
        }
        if let Some(r) = &t.report {
            placeholders("report", r, &names).map_err(|e| format!("{at}: {e}"))?;
        }
        t.errors = errors(&t.errors, &names).map_err(|e| format!("{at}: {e}"))?;
    }
    for a in &mut actions {
        let at = format!("actions/{}/action.yaml", a.id);
        for s in &a.inputs {
            conditions(&s.when, &names).map_err(|e| format!("{at}: {}: {e}", s.name))?;
        }
        for (key, text) in [
            ("error", &a.error),
            ("confirm", &a.confirm),
            ("report", &a.report),
        ] {
            if let Some(t) = text {
                placeholders(key, t, &names).map_err(|e| format!("{at}: {e}"))?;
            }
        }
        a.errors = errors(&a.errors, &names).map_err(|e| format!("{at}: {e}"))?;
    }
    let confirm = reflow_opt(&f.confirm);
    if let Some(c) = &confirm {
        placeholders("confirm", c, &names).map_err(m)?;
    }
    let module_errors = errors(&f.errors, &names).map_err(m)?;

    // Presets: named by their title and nothing else.
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
            return Err(m(format!(
                "{t}: written out in values or fetched by an action, not both"
            )));
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

    // Which actions run how, the strictest place first, and one nothing names is refused.
    let on = On {
        dashboard: f.on.dashboard,
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
                return Err(format!(
                    "{where_}: {key}: no such action: {name}, a folder under actions/"
                ));
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
        MODULE,
        "requires",
        &f.requires,
        How::Gating,
        &mut how,
        &mut queue,
    )?;
    place(
        MODULE,
        "on: dashboard",
        &on.dashboard,
        How::Opened,
        &mut how,
        &mut queue,
    )?;
    place(
        MODULE,
        "on: leave",
        &on.leave,
        How::Opened,
        &mut how,
        &mut queue,
    )?;
    place(
        MODULE,
        "on: failure",
        &on.failure,
        How::Opened,
        &mut how,
        &mut queue,
    )?;
    place(
        MODULE,
        "on: success",
        &on.success,
        How::Opened,
        &mut how,
        &mut queue,
    )?;
    for p in &presets {
        if let Some(a) = &p.action {
            place(
                MODULE,
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
        let where_ = format!("actions/{name}/action.yaml");
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
    for a in &actions {
        let at = format!("actions/{}/action.yaml", a.id);
        let Some(&h) = how.get(&a.id) else {
            return Err(format!(
                "{at}: nothing names it, so it never runs: name it under requires or on: in {MODULE} or another action"
            ));
        };
        let pages = !a.inputs.is_empty() || a.report.is_some();
        if a.tty && (pages || a.confirm.is_some()) {
            return Err(format!(
                "{at}: an action with tty has the terminal for its page"
            ));
        }
        if a.tty && !a.errors.is_empty() {
            return Err(format!(
                "{at}: errors: an action with tty runs without the trap that tells a status it chose"
            ));
        }
        if h != How::Opened && (pages || a.tty || a.confirm.is_some() || !a.errors.is_empty()) {
            return Err(format!(
                "{at}: it runs by itself where it is named, so it has no page, confirm or errors"
            ));
        }
        if h == How::Gating && a.error.is_none() {
            return Err(format!(
                "{at}: error: it runs by itself in front of the work, and a no there is read as this sentence"
            ));
        }
        if a.on_failure.contains(&a.id) {
            return Err(format!(
                "{at}: on: failure: an action cannot put itself right"
            ));
        }
        if a.qr.is_some() && a.report.is_none() {
            return Err(format!("{at}: qr: there is no report for it to appear on"));
        }
    }
    for name in &on.leave {
        let a = actions.iter().find(|a| a.id == *name).unwrap();
        if !a.inputs.is_empty() || a.confirm.is_some() {
            return Err(m("on: leave: a way out asks nothing, it only goes".into()));
        }
    }
    if let Some(ring) = ring(&actions) {
        return Err(format!("actions/: actions that wait on each other: {ring}"));
    }

    let title = text::reflow(&f.title);
    Ok(Module {
        id: id.to_string(),
        start: text::reflow(f.start.as_deref().unwrap_or("Start")),
        title,
        confirm,
        requires: f.requires,
        on,
        errors: module_errors,
        stages: f.stages,
        presets,
        settings,
        tasks,
        actions,
    })
}

/// The first ring of actions that wait on each other through their rules, written the way it
/// goes round.
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

/// `tasks/`: a folder per stage, a folder per task in it, each with task.yaml and task.sh.
fn tasks(
    files: &Files,
    dir: &str,
    stages: &[String],
    functions: &BTreeSet<String>,
) -> Result<Vec<Task>, String> {
    let base = format!("{dir}/tasks/");
    let found = files.dirs(&base);
    if found.is_empty() {
        return Err("tasks/: no tasks".into());
    }
    if let Some(file) = files.loose(&base) {
        return Err(format!(
            "tasks/{file}: a task lies in the folder of its stage, tasks/<stage>/<task>/"
        ));
    }
    let mut by_stage: BTreeMap<&str, Vec<Task>> = BTreeMap::new();
    for stage in &found {
        if !stages.contains(stage) {
            return Err(format!(
                "tasks/{stage}: no such stage, {MODULE} declares {}",
                stages.join(", ")
            ));
        }
        let ids = files.dirs(&format!("{base}{stage}/"));
        if ids.is_empty() {
            return Err(format!("tasks/{stage}: no tasks"));
        }
        for id in ids {
            let tdir = format!("{base}{stage}/{id}");
            let at = format!("tasks/{stage}/{id}");
            let f: TaskFile = yaml(files, &format!("{tdir}/task.yaml"))
                .map_err(|e| e.replace(&format!("{dir}/"), ""))?;
            if !files.has(&format!("{tdir}/task.sh")) {
                return Err(format!("{at}: no task.sh, a task does its work in one"));
            }
            if f.title.trim().is_empty() {
                return Err(format!("{at}/task.yaml: title is required"));
            }
            if !f.yes_after.is_empty() && f.confirm.is_none() {
                return Err(format!(
                    "{at}/task.yaml: yes-after: a task without confirm is never asked"
                ));
            }
            let asks = match f.asks {
                Some(a) => {
                    let name = a.name.clone();
                    if !is_name(&name)
                        || name.contains(|c: char| c.is_ascii_lowercase())
                        || name.starts_with(RESERVED)
                        || name == DRY_RUN
                    {
                        return Err(format!(
                            "{at}/task.yaml: asks: {name:?} is no variable name"
                        ));
                    }
                    if a.options.is_empty() && a.options_from.is_none() {
                        return Err(format!(
                            "{at}/task.yaml: asks: a question takes its answers from options or options-from"
                        ));
                    }
                    Some(Ask {
                        title: text::reflow(&a.title),
                        description: text::reflow(a.description.as_deref().unwrap_or_default()),
                        filter: filter(&a.filter)
                            .map_err(|e| format!("{at}/task.yaml: asks: {e}"))?,
                        options: a.options,
                        options_from: opt_shell(
                            &a.options_from,
                            "options-from",
                            &tdir,
                            files,
                            functions,
                        )
                        .map_err(|e| format!("{at}/task.yaml: asks: {e}"))?,
                        name,
                    })
                }
                None => None,
            };
            // Conditions are only parsed here; which settings they name is checked by the module.
            let mut when = Vec::new();
            for line in f.when.lines() {
                if !line.trim().is_empty() {
                    when.push(
                        Condition::parse(line).map_err(|e| format!("{at}/task.yaml: when: {e}"))?,
                    );
                }
            }
            by_stage
                .entry(stages.iter().find(|s| *s == stage).unwrap())
                .or_default()
                .push(Task {
                    id: id.clone(),
                    stage: stage.clone(),
                    dir: tdir.clone(),
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
                    test: files.has(&format!("{tdir}/test.sh")),
                });
        }
    }
    // needs stay within a stage: the stages order the rest.
    let mut out = Vec::new();
    for stage in stages {
        let Some(group) = by_stage.get(stage.as_str()) else {
            continue;
        };
        for t in group {
            for n in &t.needs {
                if n == &t.id {
                    return Err(format!("tasks/{stage}/{}: needs itself", t.id));
                }
                if !group.iter().any(|o| o.id == *n) {
                    let elsewhere = by_stage.values().flatten().find(|o| o.id == *n);
                    return Err(match elsewhere {
                        Some(o) => format!(
                            "tasks/{stage}/{}: needs {n}, which is in {}: needs orders tasks within one stage, the stages order the rest",
                            t.id, o.stage
                        ),
                        None => format!("tasks/{stage}/{}: needs unknown task: {n}", t.id),
                    });
                }
            }
        }
        let names: Vec<(String, Vec<String>)> = group
            .iter()
            .map(|t| (t.id.clone(), t.needs.clone()))
            .collect();
        let ordered = order::order(&names).map_err(|e| format!("tasks/{stage}: {e}"))?;
        out.extend(ordered.into_iter().map(|i| group[i].clone()));
    }
    for (i, t) in out.iter().enumerate() {
        for name in &t.yes_after {
            match out.iter().position(|o| o.id == *name) {
                None => {
                    return Err(format!(
                        "tasks/{}/{}: yes-after: no such task: {name}",
                        t.stage, t.id
                    ));
                }
                Some(j) if j >= i => {
                    return Err(format!(
                        "tasks/{}/{}: yes-after: {name} does not run before it",
                        t.stage, t.id
                    ));
                }
                _ => {}
            }
        }
    }
    Ok(out)
}

/// `actions/`: a folder per action, each with action.yaml and action.sh.
fn actions(files: &Files, dir: &str, functions: &BTreeSet<String>) -> Result<Vec<Action>, String> {
    let base = format!("{dir}/actions/");
    let mut out = Vec::new();
    for id in files.dirs(&base) {
        let adir = format!("{base}{id}");
        let at = format!("actions/{id}/action.yaml");
        let f: ActionFile = yaml(files, &format!("{adir}/action.yaml"))
            .map_err(|e| e.replace(&format!("{dir}/"), ""))?;
        if !files.has(&format!("{adir}/action.sh")) {
            return Err(format!(
                "actions/{id}: no action.sh, an action does its work in one"
            ));
        }
        if f.title.trim().is_empty() {
            return Err(format!("{at}: title is required"));
        }
        let mut inputs = Vec::new();
        for s in f.inputs {
            let name = s.name.clone();
            if s.first || s.group.is_some() || s.value_from.is_some() {
                return Err(format!(
                    "{at}: {name}: an input is asked when its action is opened, so it takes no first, group or value-from"
                ));
            }
            let s = setting(s, &adir, files, functions).map_err(|e| format!("{at}: {e}"))?;
            if inputs.iter().any(|o: &Setting| o.name == s.name) {
                return Err(format!("{at}: {} is declared twice", s.name));
            }
            inputs.push(s);
        }
        out.push(Action {
            id: id.clone(),
            dir: adir,
            title: text::reflow(&f.title),
            description: text::reflow(f.description.as_deref().unwrap_or_default()),
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

    /// A small product in memory: a module with two stages, a question, a gate and a way out.
    pub fn fixture() -> Vec<(&'static str, &'static [u8])> {
        vec![
            ("product.yaml", b"title: Tux\naccent: \"#8fbcbb\"\nconsole-accent: cyan\nlogo: |\n  Tux\n\n  ####\nstatus:\n  check: check_online()\n  pass: Online\n  fail: Offline\n"),
            ("lib.sh", b"check_online() { true; }\noptions_disks() { printf 'sda\\tsda 20G\\nsdb\\tsdb 40G\\n'; }\nprefill_host() { echo tuxbox; }\nvalue_vm() { echo false; }\napply_keymap() { true; }\n"),
            ("setup/module.yaml", b"title: Setup\nstart: Install now\nconfirm: |\n  Install on {{TUX_DISK}}?\n\n  Everything on it is erased.\nrequires: [root]\non:\n  dashboard: [note]\n  leave: [restart]\n  failure: [share]\n  success: [shell]\nerrors:\n  3: |\n    No internet\n\n    Connect and start again.\nstages: [prepare, install]\npresets:\n  - title: Desktop\n    description: A desktop.\n    values:\n      TUX_DESKTOP: gnome\n  - title: Core\n    values:\n      TUX_DESKTOP: none\nsettings:\n  - name: TUX_KEYMAP\n    type: list\n    title: Keyboard\n    group: Region\n    required: true\n    first: true\n    options: [us, de]\n    apply: apply_keymap()\n  - name: TUX_HOST\n    type: text\n    title: Hostname\n    description: What the machine calls itself.\n    group: System\n    required: true\n    prefill: prefill_host()\n    pattern: '^[a-z][a-z0-9-]*$'\n    error: Lower case letters, digits and - only.\n  - name: TUX_DESKTOP\n    type: list\n    title: Desktop\n    group: System\n    required: true\n    options: [gnome, none]\n  - name: TUX_DRIVER\n    type: list\n    title: Driver\n    group: System\n    required: true\n    options: [free, none]\n    when: TUX_DESKTOP != none\n  - name: TUX_DISK\n    type: list\n    title: Disk\n    group: Storage\n    required: true\n    options-from: options_disks()\n    pattern: '^sd'\n  - name: TUX_ENCRYPT\n    type: bool\n    title: Encryption\n    group: Storage\n    default: true\n  - name: TUX_PASSWORD\n    type: new-password\n    title: Password\n    group: System\n    required: true\n  - name: TUX_VM\n    type: bool\n    title: Virtual machine\n    group: System\n    value-from: value_vm()\n"),
            ("setup/tasks/prepare/disk/task.yaml", b"title: Prepare the disk\nerrors:\n  10: |\n    The disk is gone\n\n    {{TUX_DISK}} is not there.\n"),
            ("setup/tasks/prepare/disk/task.sh", b"echo \"$TUX_DISK\" >\"${MODULE_CONF%/*}/disk\"\n"),
            ("setup/tasks/prepare/disk/test.sh", b"[ -f \"${MODULE_CONF%/*}/disk\" ]\n"),
            ("setup/tasks/install/base/task.yaml", b"title: Install the base\nneeds: [snapshot]\nreport: |\n  Installed\n\n  {{TUX_HOST}} is ready.\nerrors:\n  10: |\n    The name is taken\n\n    {{TUX_HOST}} is on the network already.\n"),
            ("setup/tasks/install/base/task.sh", b"[ \"$TUX_HOST\" != taken ] || exit 10\n[ \"$TUX_HOST\" != broken ] || false\necho \"$TUX_HOST\" >\"${MODULE_CONF%/*}/host\"\n"),
            ("setup/tasks/install/desktop/task.yaml", b"title: Install the desktop\nneeds: [base]\nwhen: TUX_DESKTOP != none\nallow-failure: true\n"),
            ("setup/tasks/install/desktop/task.sh", b"[ \"$TUX_DRIVER\" = free ]\n"),
            ("setup/tasks/install/snapshot/task.yaml", b"title: Go back to a snapshot\nasks:\n  name: TUX_SNAPSHOT\n  title: Snapshot\n  options-from: ./snapshots.sh\nconfirm: |\n  Put {{TUX_SNAPSHOT}} in place?\n"),
            ("setup/tasks/install/snapshot/task.sh", b"echo \"$TUX_SNAPSHOT\"\n"),
            ("setup/tasks/install/snapshot/snapshots.sh", b"echo one\necho two\n"),
            ("setup/actions/root/action.yaml", b"title: Running as root\nerror: This has to run as root.\n"),
            ("setup/actions/root/action.sh", b"[ \"$(id -u)\" -eq 0 ]\n"),
            ("setup/actions/note/action.yaml", b"title: Leave a note\ndescription: Writes a note.\ninputs:\n  - name: TUX_NOTE\n    type: text\n    title: Note\n    required: true\nreport: |\n  Noted\n\n  {{TUX_NOTE}} is written down.\n"),
            ("setup/actions/note/action.sh", b"echo \"$TUX_NOTE\"\n"),
            ("setup/actions/restart/action.yaml", b"title: Restart\ndescription: Starts the machine again.\n"),
            ("setup/actions/restart/action.sh", b"true\n"),
            ("setup/actions/share/action.yaml", b"title: Share the log\ndescription: Puts the log online.\nreport: |\n  Shared\nqr: TUX_URL\nsimulates: true\n"),
            ("setup/actions/share/action.sh", b"printf \"TUX_URL='https://x/1'\\n\" >>\"$MODULE_CONF\"\n"),
            ("setup/actions/shell/action.yaml", b"title: Open a shell\ndescription: Until exit.\ntty: true\n"),
            ("setup/actions/shell/action.sh", b"true\n"),
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

    /// A product of one module whose tasks and actions name nothing, with the module.yaml given.
    fn tiny(module: &'static str) -> Vec<(&'static str, &'static [u8])> {
        vec![
            ("product.yaml", b"title: Tux\n"),
            ("lib.sh", b"fn_a() { true; }\n"),
            ("m/module.yaml", module.as_bytes()),
            ("m/tasks/a/one/task.yaml", b"title: One\n"),
            ("m/tasks/a/one/task.sh", b"true\n"),
            ("m/actions/root/action.yaml", b"title: Root\nerror: No\n"),
            ("m/actions/root/action.sh", b"true\n"),
            ("m/actions/row/action.yaml", b"title: Row\n"),
            ("m/actions/row/action.sh", b"true\n"),
            (
                "m/actions/asks/action.yaml",
                b"title: Asks\ninputs:\n  - name: A_IN\n    type: text\n    title: In\n",
            ),
            ("m/actions/asks/action.sh", b"true\n"),
        ]
    }

    fn refused(files: &[(&str, &[u8])], says: &str) {
        let err = load(files)
            .err()
            .unwrap_or_else(|| panic!("loaded, wanted {says:?}"));
        assert!(err.contains(says), "{err:?} does not say {says:?}");
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
        assert_eq!(
            m.tasks[0].errors[&10],
            "The disk is gone\n\n{{TUX_DISK}} is not there."
        );
        assert!(m.tasks[0].test && !m.tasks[1].test);
        assert_eq!(
            m.confirm.as_deref(),
            Some("Install on {{TUX_DISK}}?\n\nEverything on it is erased.")
        );
        assert_eq!(
            m.setting("TUX_DRIVER").unwrap().when[0].to_string(),
            "TUX_DESKTOP != none"
        );
        assert_eq!(m.setting("TUX_KEYMAP").unwrap().filter(), Filter::Open);
        assert_eq!(
            m.tasks[1].asks.as_ref().unwrap().options_from,
            Some(Shell::File(
                "setup/tasks/install/snapshot/snapshots.sh".into()
            ))
        );
        assert!(m.declared().contains(&"TUX_URL") && m.declared().contains(&"TUX_NOTE"));
        assert!(m.texts().contains(&"Install now".to_string()));
        assert_eq!(l.texts()[..2], ["Online", "Offline"]);
    }

    #[test]
    fn refuses_what_cannot_run() {
        const OK: &str =
            "title: M\nstages: [a]\nrequires: [root]\non:\n  dashboard: [asks]\n  leave: [row]\n";
        assert!(load(&tiny(OK)).is_ok());
        refused(
            &tiny(
                "title: M\nstages: [a]\nrequires: [root]\non:\n  dashboard: [asks, row]\nsettings:\n  - name: lower\n    type: text\n    title: T\n",
            ),
            "no variable name",
        );
        refused(
            &tiny(
                "title: M\nstages: [a]\nrequires: [root]\non:\n  dashboard: [asks, row]\nsettings:\n  - name: MODULE_X\n    type: text\n    title: T\n",
            ),
            "belong to the runtime",
        );
        refused(
            &tiny(
                "title: M\nstages: [a]\nrequires: [root]\non:\n  dashboard: [asks, row]\nsettings:\n  - name: A\n    type: text\n    title: T\n    options: [x]\n",
            ),
            "takes no options",
        );
        refused(
            &tiny(
                "title: M\nstages: [a]\nrequires: [root]\non:\n  dashboard: [asks, row]\nsettings:\n  - name: A\n    type: list\n    title: T\n",
            ),
            "options or options-from",
        );
        refused(
            &tiny(
                "title: M\nstages: [a]\nrequires: [root]\non:\n  dashboard: [asks, row]\nsettings:\n  - name: A\n    type: text\n    title: T\n    prefill: nothing()\n",
            ),
            "not a function in lib.sh",
        );
        refused(
            &tiny(
                "title: M\nstages: [a]\nrequires: [root]\non:\n  dashboard: [asks, row]\nsettings:\n  - name: A\n    type: text\n    title: T\n    when: B == 1\n",
            ),
            "no such setting: B",
        );
        refused(
            &tiny(
                "title: M\nstages: [a]\nrequires: [root]\non:\n  dashboard: [asks, row]\nerrors:\n  200: Too high\n",
            ),
            "from 1 to 125",
        );
        refused(
            &tiny(
                "title: M\nstages: [a]\nrequires: [root]\non:\n  dashboard: [asks, row]\nconfirm: Erase {{NOPE}}?\n",
            ),
            "{{NOPE}} is not a variable",
        );
        refused(
            &tiny("title: M\nstages: [a]\nrequires: [nope]\n"),
            "no such action: nope",
        );
        refused(&tiny("title: M\nstages: [a]\n"), "nothing names it");
        refused(
            &tiny("title: M\nstages: [a]\nrequires: [root, asks]\non:\n  leave: [row]\n"),
            "has no page",
        );
        refused(
            &tiny("title: M\nstages: [a]\nrequires: [root, row]\non:\n  dashboard: [asks]\n"),
            "read as this sentence",
        );
        refused(
            &tiny(
                "title: M\nstages: [a]\nrequires: [root]\non:\n  leave: [asks]\n  dashboard: [row]\n",
            ),
            "a way out asks nothing",
        );
        refused(
            &tiny("title: M\nstages: [b]\nrequires: [root]\non:\n  dashboard: [asks, row]\n"),
            "no such stage",
        );
        refused(
            &with(
                "setup/tasks/install/base/task.yaml",
                "title: B\nneeds: [disk]\n",
            ),
            "which is in prepare",
        );
        refused(
            &with(
                "setup/tasks/install/base/task.yaml",
                "title: B\nneeds: [desktop]\n",
            ),
            "wait on each other",
        );
        refused(
            &with(
                "setup/tasks/install/base/task.yaml",
                "title: B\nyes-after: [disk]\n",
            ),
            "without confirm",
        );
        refused(
            &with(
                "setup/tasks/install/base/task.yaml",
                "title: B\nunknown: 1\n",
            ),
            "unknown",
        );
        refused(
            &with(
                "setup/tasks/prepare/disk/task.yaml",
                "title: D\nasks:\n  name: TUX_HOST\n  title: H\n  options: [a]\n",
            ),
            "is a setting already",
        );
        refused(
            &with(
                "setup/actions/shell/action.yaml",
                "title: S\ntty: true\nreport: Done\n",
            ),
            "terminal for its page",
        );
        refused(
            &with("setup/actions/share/action.yaml", "title: S\nqr: TUX_URL\n"),
            "no report for it",
        );
        refused(
            &with(
                "setup/actions/root/action.yaml",
                "title: R\nerror: No\nrequires: [root]\n",
            ),
            "wait on each other",
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

    #[test]
    fn reads_the_functions_of_a_library() {
        let f = functions("a() {\n}\nfunction b {\n}\n  c () { :; }\nnot a definition\n# d() {\n");
        assert_eq!(f.into_iter().collect::<Vec<_>>(), ["a", "b", "c"]);
    }
}

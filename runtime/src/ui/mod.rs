//! The interface: pages on a stack, drawn into a cell grid the terminal shows.

mod app;
mod detail;
mod draw;
mod input;
mod list;
mod pages;
mod qr;
mod style;

pub use app::App;
pub use style::Style;

use std::collections::BTreeMap;
use std::sync::mpsc::Sender;
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};

use crate::script::{self, Failure, Session};
use crate::spec::{self, Module, Setting};
use crate::store::Store;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Key {
    Char(char),
    Ctrl(char),
    Enter,
    Esc,
    Backspace,
    Delete,
    Tab,
    Up,
    Down,
    Left,
    Right,
    PageUp,
    PageDown,
    Home,
    End,
    /// A notch of the mouse wheel: a list moves as with the arrows.
    WheelUp,
    WheelDown,
}

/// What a key means outside a text box. In front of one, only the keys that cannot be typed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Nav {
    Up,
    Down,
    PageUp,
    PageDown,
    Top,
    Bottom,
    Open,
    Back,
    Quit,
    Filter,
}

impl Key {
    pub fn nav(self, typing: bool) -> Option<Nav> {
        let nav = match self {
            Key::Up | Key::WheelUp => Nav::Up,
            Key::Down | Key::WheelDown => Nav::Down,
            Key::PageUp => Nav::PageUp,
            Key::PageDown => Nav::PageDown,
            Key::Enter => Nav::Open,
            Key::Esc => Nav::Back,
            Key::Ctrl('c') => Nav::Quit,
            _ if typing => return None,
            Key::Home | Key::Char('g') => Nav::Top,
            Key::End | Key::Char('G') => Nav::Bottom,
            Key::Char('k') => Nav::Up,
            Key::Char('j') => Nav::Down,
            Key::Char('l') | Key::Right => Nav::Open,
            Key::Char('h') | Key::Left | Key::Backspace => Nav::Back,
            Key::Char('q') => Nav::Quit,
            Key::Char('f') | Key::Char('/') => Nav::Filter,
            _ => return None,
        };
        Some(nav)
    }

    /// Whether holding the key repeats it: moving and typing do, everything else happens once
    /// per press, so a held enter answers no question that follows.
    pub fn repeats(self, typing: bool) -> bool {
        matches!(
            self.nav(false),
            Some(Nav::Up | Nav::Down | Nav::PageUp | Nav::PageDown)
        ) || typing && matches!(self, Key::Char(_) | Key::Backspace)
    }
}

/// The step of what moves: a running bar moves a cell, the spinner turns every third. The driver
/// wakes on the beat, so every frame stands exactly as long as the next.
pub const BEAT: Duration = Duration::from_millis(40);
/// A frame of what moves smoothly, and the shortest time between two draws.
pub const FRAME: Duration = Duration::from_millis(16);
/// The beat of a page where nothing moves.
const IDLE: Duration = Duration::from_millis(500);

/// The start every animation counts from.
fn epoch() -> Instant {
    static EPOCH: OnceLock<Instant> = OnceLock::new();
    *EPOCH.get_or_init(Instant::now)
}

/// Beats of `pace` passed by `now`.
pub fn beats(now: Instant, pace: Duration) -> u64 {
    (now.saturating_duration_since(epoch()).as_nanos() / pace.as_nanos()) as u64
}

/// The first beat of `pace` after `now`, or the start where `now` lies before it.
fn next_beat(now: Instant, pace: Duration) -> Instant {
    let start = epoch();
    if now < start {
        return start;
    }
    start + Duration::from_nanos((beats(now, pace) + 1) * pace.as_nanos() as u64)
}

pub type PageId = u64;

/// A script given the terminal, which the driver runs between two frames.
pub type Handover = Box<dyn FnOnce() -> Result<(), Box<Failure>> + Send>;

/// What a job a page started comes back with.
pub enum Data {
    Said(pages::gate::Said),
    Answers(pages::question::Answers),
    Unoffered(pages::dashboard::Unoffered),
    Tried(pages::password::Tried),
    Done(Result<(), Box<Failure>>),
    /// What ran behind the page that left has stopped.
    Halted,
}

impl From<pages::password::Tried> for Data {
    fn from(tried: pages::password::Tried) -> Data {
        Data::Tried(tried)
    }
}

impl From<pages::gate::Said> for Data {
    fn from(said: pages::gate::Said) -> Data {
        Data::Said(said)
    }
}

impl From<pages::question::Answers> for Data {
    fn from(answers: pages::question::Answers) -> Data {
        Data::Answers(answers)
    }
}

impl From<pages::dashboard::Unoffered> for Data {
    fn from(unoffered: pages::dashboard::Unoffered) -> Data {
        Data::Unoffered(unoffered)
    }
}

impl From<Result<(), Box<Failure>>> for Data {
    fn from(done: Result<(), Box<Failure>>) -> Data {
        Data::Done(done)
    }
}

pub enum Msg {
    Key(Key),
    /// A key held down, sent again by the keyboard's repeat.
    Held(Key),
    Tick,
    Resize,
    /// The result of a job a page started.
    Data(PageId, Data),
    /// An event of a script a page started.
    Run(PageId, script::Event),
    /// What the header's status check answered.
    Status(bool),
    /// Whether this machine has an action, as what it requires said.
    Offered(String, bool),
    /// A value read off the machine.
    Resolved(String, String),
    /// Text pasted into the terminal as one, typed where a text box has the keys.
    Paste(String),
}

pub enum Flow {
    Stay,
    /// The key meant nothing here. The app applies back, quit and abort.
    Ignored,
    Push(Box<dyn Page>),
    Replace(Box<dyn Page>),
    Pop,
    /// Several pages at once: an action's, once it has worked.
    PopN(usize),
    /// Everything but the dashboard goes.
    Home,
    Quit,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Tone {
    Normal,
    Muted,
    Accent,
    Ok,
    Warn,
    Error,
}

pub trait Page {
    /// The page's name in the header path. Empty adds nothing.
    fn title(&self) -> String;
    fn draw(
        &mut self,
        area: ratatui::layout::Rect,
        buf: &mut ratatui::buffer::Buffer,
        ctx: &mut Ctx,
    );
    /// The keys the footer names, as key and what it does.
    fn hints(&self, ctx: &Ctx) -> Vec<(&'static str, String)>;
    fn key(&mut self, key: Key, ctx: &mut Ctx) -> Flow;
    fn data(&mut self, _data: Data, _ctx: &mut Ctx) -> Flow {
        Flow::Stay
    }
    fn run(&mut self, _event: script::Event, _ctx: &mut Ctx) -> Flow {
        Flow::Stay
    }
    fn tick(&mut self, _ctx: &mut Ctx) -> Flow {
        Flow::Stay
    }
    /// A text box has the keys, so letters are typed rather than read as commands.
    fn typing(&self) -> bool {
        false
    }
    /// Moves by itself, so the driver wakes on every beat.
    fn animating(&self, _ctx: &Ctx) -> bool {
        false
    }
    /// The beat it moves on while animating, the spinner's unless it moves smoothly.
    fn pace(&self) -> Duration {
        BEAT
    }
    /// Drawn on the whole screen, without the header and the keys.
    fn bare(&self) -> bool {
        false
    }
    /// Nothing is behind it: back means leaving, as on a run that is under way.
    fn holds(&self) -> bool {
        false
    }
    /// The way out itself, which leaving does not open twice.
    fn leaving(&self) -> bool {
        false
    }
    /// Something runs on it that must not outlive the program: the page gives it up, and its
    /// script is handed over to be stopped.
    fn stop(&mut self, _ctx: &mut Ctx) -> Option<Session> {
        None
    }
    /// On top again after the page above it closed.
    fn resumed(&mut self, _ctx: &mut Ctx) -> Flow {
        Flow::Stay
    }
    /// A note for the header's right, in place of the status: where a question stands in a run.
    fn note(&self, _ctx: &Ctx) -> Option<String> {
        None
    }
    /// Whether it is the dashboard, where every trail starts and none is drawn.
    fn home(&self) -> bool {
        false
    }
    /// The trail in the header starts over here: a run of pages one after another rather than
    /// one inside the other.
    fn root(&self) -> bool {
        false
    }
}

pub struct Ctx {
    pub module: &'static Module,
    pub store: Store,
    pub style: Style,
    /// The machine is only this program: leaving closes it for whatever starts it again.
    pub kiosk: bool,
    /// What the header's status check last said, none before it has answered.
    pub status: Option<bool>,
    /// Which actions this machine has, as what they require last said. One that requires
    /// nothing is there without asking.
    pub offered: BTreeMap<String, bool>,
    /// The machine had answered nothing when the program started, read once before the first save.
    pub first: bool,
    /// What the work requires has said yes this session.
    pub gated: bool,
    /// The profiles were offered this session.
    pub presets_seen: bool,
    /// How many questions the opening run of questions began with, for its counter.
    pub wizard: usize,
    /// An action fetched answers into the file, which the page below reads back.
    pub imported: bool,
    /// A yes or no just given on a page of its own, for the page that asked.
    pub answered: Option<bool>,
    /// Leaving became a decision on this page: everything running behind it is stopped, and the
    /// page is told once it has.
    pub halt: Option<PageId>,
    /// Something runs behind the page in front that leaving stops.
    pub behind: bool,
    /// The status is read again as soon as this is set: an action may have changed it.
    pub recheck: std::cell::Cell<bool>,
    /// A script to hand the terminal to, which the driver does between two frames.
    pub handover: Option<Handover>,
    /// Where a text box is typed into this frame, for the terminal's own cursor.
    pub cursor: std::cell::Cell<Option<(u16, u16)>>,
    /// Background reads under way, for the spinner.
    pending: std::cell::Cell<usize>,
    tx: Sender<Msg>,
    wake: Arc<dyn Fn() + Send + Sync>,
    page: PageId,
}

impl Ctx {
    /// Runs a job off the drawing thread. Its result arrives at the page that started it.
    pub fn spawn<T: Into<Data> + Send + 'static>(&self, job: impl FnOnce() -> T + Send + 'static) {
        let (tx, wake, page) = (self.tx.clone(), self.wake.clone(), self.page);
        self.pending.set(self.pending.get() + 1);
        std::thread::spawn(move || {
            let result = job();
            let _ = tx.send(Msg::Data(page, result.into()));
            wake();
        });
    }

    /// Where the events of a script go: to the page that started it.
    pub fn run_sink(&self) -> impl Fn(script::Event) + Send + Sync + 'static {
        let (tx, wake, page) = (self.tx.clone(), self.wake.clone(), self.page);
        move |e| {
            let _ = tx.send(Msg::Run(page, e));
            wake();
        }
    }

    pub fn page_id(&self) -> PageId {
        self.page
    }

    pub fn take_handover(&mut self) -> Option<Handover> {
        self.handover.take()
    }

    pub fn product_title(&self) -> String {
        spec::loaded().product.title.clone()
    }

    pub fn module_status(&self) -> Option<&'static spec::Status> {
        spec::loaded().product.status.as_ref()
    }

    /// Something loads in the background, which the header shows.
    pub fn busy(&self) -> bool {
        self.pending.get() > 0
    }

    /// Whether this machine has an action: every action it requires said yes. Until that has
    /// said, the row is not shown.
    pub fn has(&self, action: &spec::Action) -> bool {
        action.requires.is_empty() || self.offered.get(&action.id).copied().unwrap_or(false)
    }

    /// The actions a list of names stands for that this machine has, in its order.
    pub fn rows(&self, names: &[String]) -> Vec<&'static spec::Action> {
        self.module
            .named(names)
            .into_iter()
            .filter(|a| self.has(a))
            .collect()
    }

    /// The first action an action names on failure that this machine has.
    pub fn fallback(&self, action: &spec::Action) -> Option<&'static spec::Action> {
        self.rows(&action.on_failure).into_iter().next()
    }

    /// Asks, off the drawing thread, whether this machine has each action that requires others.
    /// An answer stands until the next look replaces it, so a row does not blink out meanwhile.
    pub fn look(&self) {
        let env = self.store.env();
        for action in &self.module.actions {
            if action.requires.is_empty() {
                continue;
            }
            let checks: Vec<spec::Shell> = self
                .module
                .named(&action.requires)
                .iter()
                .map(|a| a.run.clone())
                .collect();
            let (tx, wake, id, env) = (
                self.tx.clone(),
                self.wake.clone(),
                action.id.clone(),
                env.clone(),
            );
            let dry = self.store.dry_run();
            std::thread::spawn(move || {
                let yes = dry || checks.iter().all(|c| script::guard(c, &env).is_ok());
                let _ = tx.send(Msg::Offered(id, yes));
                wake();
            });
        }
    }

    /// Reads every value the module reads off the machine, off the drawing thread. A script
    /// that fails leaves the value empty, as an unanswered question is.
    pub fn resolve(&self) {
        let env = self.store.env();
        for s in &self.module.settings {
            let Some(shell) = &s.value_from else { continue };
            let (tx, wake, name, shell, env) = (
                self.tx.clone(),
                self.wake.clone(),
                s.name.clone(),
                shell.clone(),
                env.clone(),
            );
            std::thread::spawn(move || {
                let value = match script::run(&shell, &env) {
                    Ok(v) => v,
                    Err(e) => {
                        crate::warn!("value-from for {name}: {e}");
                        String::new()
                    }
                };
                let _ = tx.send(Msg::Resolved(name, value));
                wake();
            });
        }
    }

    /// Puts an answer into effect on this machine, such as the console keyboard, which has to be
    /// loaded before the next thing is typed, so this waits for it. A failure is logged and the
    /// answer stands: whoever chose it sees whether the keyboard changed.
    pub fn apply(&self, s: &Setting) -> Result<(), String> {
        let Some(shell) = &s.apply else { return Ok(()) };
        script::run(shell, &self.store.env())
            .map(|_| ())
            .inspect_err(|e| {
                crate::warn!("apply for {}: {e}", s.name);
            })
    }

    /// Puts every standing answer in force again, off the drawing thread: at the start, and after
    /// a profile, whose values no prompt applied one by one. One that cannot be put in
    /// force goes back to its default and is asked again, since nobody watched it fail.
    pub fn settle(&self) {
        let env = self.store.env();
        for s in &self.module.settings {
            let Some(shell) = &s.apply else { continue };
            if self.store.get(&s.name).is_empty() {
                continue;
            }
            let (tx, wake, name, default, shell, env) = (
                self.tx.clone(),
                self.wake.clone(),
                s.name.clone(),
                s.default.clone(),
                shell.clone(),
                env.clone(),
            );
            std::thread::spawn(move || {
                if let Err(e) = script::run(&shell, &env) {
                    crate::warn!("apply for {name}: {e}");
                    let _ = tx.send(Msg::Resolved(name, default));
                    wake();
                }
            });
        }
    }

    /// Writes the answer file. A failure is logged: an unsaved run asks again from the top.
    pub fn save(&self) {
        if let Err(e) = self.store.save() {
            crate::error!("{}: {e}", self.store.path().display());
        }
    }

    /// The answers as a sentence reads them: a bool in words, everything else as it stands.
    pub fn expand(&self, text: &str) -> String {
        spec::text::expand(text, |name| crate::store::label(self.store.get(name)))
    }

    /// A step of this module, for the shell layer.
    pub fn step(&self, name: &str, action: bool, run: spec::Shell) -> script::Step {
        script::Step {
            module: crate::i18n::t(&self.module.title),
            name: name.to_string(),
            action,
            run,
        }
    }

    /// The answers a shell gets, with the environment of this process under them.
    pub fn env(&self) -> Vec<(String, String)> {
        self.store.env()
    }

    /// The way out: a question where the module says how the machine is put down, or in a kiosk.
    pub fn leaves(&self) -> bool {
        self.kiosk || self.module.leaves()
    }
}

/// What a failure means in the module's own words, where its script stopped itself with a
/// status they cover: own first, then the module's.
pub fn told(module: &Module, own: &BTreeMap<i32, String>, f: &Failure) -> Option<String> {
    if !f.deliberate {
        return None;
    }
    module.told(own, f.code).map(crate::i18n::t)
}

/// Every character outside ASCII the interface can put on a console, in code point order: the
/// console glyphs, the wordmark, every word of every catalog and every sentence of the product.
pub fn glyphs() -> String {
    let mut chars: std::collections::BTreeSet<char> = std::collections::BTreeSet::new();
    let mut add = |s: &str| chars.extend(s.chars().filter(|c| !c.is_ascii()));
    for g in style::CONSOLE.all() {
        add(g);
    }
    for row in detail::TICK.iter().chain(detail::CROSS.iter()) {
        add(row);
    }
    for row in qr::CELLS {
        add(row);
    }
    for line in &spec::loaded().product.logo {
        add(line);
    }
    for word in crate::i18n::translations() {
        add(word);
    }
    for text in spec::loaded().texts() {
        add(&text);
    }
    add(pages::language::CHOOSE);
    chars.into_iter().collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_beat_falls_on_the_grid_whenever_it_is_asked_for() {
        let start = epoch();
        for offset in [0, 1, 119, 120, 121, 500, 12_345] {
            let now = start + Duration::from_millis(offset);
            let next = next_beat(now, BEAT);
            assert!(next > now);
            assert!(next - now <= BEAT);
            assert_eq!((next - start).as_nanos() % BEAT.as_nanos(), 0, "{offset}");
        }
    }
}

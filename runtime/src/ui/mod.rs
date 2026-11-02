//! Terminal UI: a page stack drawn into a cell buffer.

pub(crate) mod app;
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
    AltBackspace,
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
    WheelUp,
    WheelDown,
}

/// Navigation meaning of a key. In a text box, only keys that cannot be typed have one.
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

    /// Only moving and typing repeat when held, so a held enter does not answer the next question.
    pub fn repeats(self, typing: bool) -> bool {
        matches!(
            self.nav(false),
            Some(Nav::Up | Nav::Down | Nav::PageUp | Nav::PageDown)
        ) || typing && matches!(self, Key::Char(_) | Key::Backspace | Key::AltBackspace)
    }
}

/// What a key does, as the footer names it. Every page takes its words from here, and they are
/// the System Manager's, so one deed reads the same in every Arch OS program.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Does {
    Choose,
    Scroll,
    Open,
    Run,
    Answer,
    Use,
    Details,
    Compact,
    Filter,
    CloseFilter,
    Reload,
    Continue,
    /// Back, where that leads to the dashboard.
    Back,
    Menu,
    /// Back to the step before on the same page, so never the dashboard.
    Return,
    Stop,
    Quit,
}

impl Does {
    pub fn label(self) -> String {
        use crate::i18n::t;
        match self {
            Does::Choose => t("choose"),
            Does::Scroll => t("scroll"),
            Does::Open => t("open"),
            Does::Run => t("run"),
            Does::Answer => t("answer"),
            Does::Use => t("use"),
            Does::Details => t("details"),
            Does::Compact => t("compact"),
            Does::Filter => t("filter"),
            Does::CloseFilter => t("close filter"),
            Does::Reload => t("reload"),
            Does::Continue => t("continue"),
            Does::Back => t("back"),
            Does::Menu => t("dashboard"),
            Does::Return => t("back"),
            Does::Stop => t("stop"),
            Does::Quit => t("quit"),
        }
    }
}

/// Animation step: a running bar moves one cell per beat, the spinner every third. Waking on the
/// beat keeps frames evenly spaced.
pub const BEAT: Duration = Duration::from_millis(40);
/// Frame of smooth motion, and the minimum time between two draws.
pub const FRAME: Duration = Duration::from_millis(16);
/// Beat of a page without animation.
const IDLE: Duration = Duration::from_millis(500);

fn epoch() -> Instant {
    static EPOCH: OnceLock<Instant> = OnceLock::new();
    *EPOCH.get_or_init(Instant::now)
}

pub fn beats(now: Instant, pace: Duration) -> u64 {
    (now.saturating_duration_since(epoch()).as_nanos() / pace.as_nanos()) as u64
}

fn next_beat(now: Instant, pace: Duration) -> Instant {
    let start = epoch();
    if now < start {
        return start;
    }
    start + Duration::from_nanos((beats(now, pace) + 1) * pace.as_nanos() as u64)
}

pub type PageId = u64;

/// Script that takes over the terminal, run by the driver between two frames.
pub type Handover = Box<dyn FnOnce() -> Result<(), Box<Failure>> + Send>;

/// Result of a page's background job.
pub enum Data {
    Said(pages::gate::Said),
    Answers(pages::question::Answers),
    Unoffered(pages::dashboard::Unoffered),
    Tried(pages::password::Tried),
    Done(Result<(), Box<Failure>>),
    /// Everything running behind the leaving page has stopped.
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
    /// Keyboard repeat of a held key.
    Held(Key),
    Tick,
    Resize,
    Data(PageId, Data),
    Run(PageId, script::Event),
    /// Result of the header's status check.
    Status(bool),
    /// Action id and whether its requirements hold on this machine.
    Offered(String, bool),
    /// Setting name and the value read off the machine.
    Resolved(String, String),
    /// Bracketed paste, typed into a focused text box.
    Paste(String),
    /// SIGTERM, SIGHUP or SIGINT: the work stops and the program ends.
    Stop,
}

pub enum Flow {
    Stay,
    /// Key unused by the page. The app then handles back, quit and abort.
    Ignored,
    Push(Box<dyn Page>),
    Replace(Box<dyn Page>),
    Pop,
    /// Several pages at once, such as an action's after it succeeds.
    PopN(usize),
    /// Pops all pages but the dashboard.
    Home,
    Quit,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Tone {
    Normal,
    Muted,
    Accent,
    /// Cursor row and its mark, on the surface background.
    Current,
    Ok,
    Warn,
    Error,
}

pub trait Page {
    /// Name in the header path. Empty adds no segment.
    fn title(&self) -> String;
    /// Name in the trace, free of any text on screen.
    fn id(&self, ctx: &Ctx) -> String;
    /// Id of the row under the cursor, for the trace.
    fn focus(&self) -> Option<String> {
        None
    }
    fn draw(
        &mut self,
        area: ratatui::layout::Rect,
        buf: &mut ratatui::buffer::Buffer,
        ctx: &mut Ctx,
    );
    /// Footer keys as key and deed.
    fn hints(&self, ctx: &Ctx) -> Vec<(&'static str, Does)>;
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
    /// A text box has focus, so letters are typed instead of read as commands.
    fn typing(&self) -> bool {
        false
    }
    /// The driver wakes on every beat.
    fn animating(&self, _ctx: &Ctx) -> bool {
        false
    }
    /// Beat while animating. Smooth motion overrides the spinner beat.
    fn pace(&self) -> Duration {
        BEAT
    }
    /// Full screen, without header and footer.
    fn bare(&self) -> bool {
        false
    }
    /// Back leaves instead of popping, as during a run.
    fn holds(&self) -> bool {
        false
    }
    /// Work runs that leaving stops, so the leave page warns of it.
    fn running(&self) -> bool {
        false
    }
    /// The leave page itself, so leaving does not open it twice.
    fn leaving(&self) -> bool {
        false
    }
    /// Hands over a running script that must not outlive the program, to be stopped.
    fn stop(&mut self, _ctx: &mut Ctx) -> Option<Session> {
        None
    }
    /// Back on top after the page above closed.
    fn resumed(&mut self, _ctx: &mut Ctx) -> Flow {
        Flow::Stay
    }
    /// Flow without a person at the keyboard, or why the page needs one.
    fn unattended(&mut self, _ctx: &mut Ctx) -> Result<Flow, String> {
        Err(crate::i18n::tf(
            "{{page}} needs a person at the keyboard.",
            &[("page", &self.title())],
        ))
    }
    /// Outcome once done, in the text the page shows.
    fn finished(&self, _ctx: &Ctx) -> Option<Result<String, String>> {
        None
    }
    /// Header right side in place of the status, such as the question counter of a run.
    fn note(&self, _ctx: &Ctx) -> Option<String> {
        None
    }
    /// The dashboard. The header path starts here and is not drawn.
    fn home(&self) -> bool {
        false
    }
    /// The header path restarts here, for pages in sequence instead of nested.
    fn root(&self) -> bool {
        false
    }
}

pub struct Ctx {
    pub module: &'static Module,
    pub store: Store,
    pub style: Style,
    /// The machine runs only this program. Leaving exits to whatever starts it again.
    pub kiosk: bool,
    /// Last status check result, `None` before the first.
    pub status: Option<bool>,
    /// Last requirement check per action id. Actions without requirements never appear.
    pub offered: BTreeMap<String, bool>,
    /// No answer file existed at start. Read once before the first save.
    pub first: bool,
    /// The requirements gate passed this session.
    pub gated: bool,
    pub presets_seen: bool,
    /// Question count at the start of the opening wizard, for its counter.
    pub wizard: usize,
    /// An action wrote answers into the file, for the page below to read back.
    pub imported: bool,
    /// Yes or no from a confirm page, for the page that asked.
    pub answered: Option<bool>,
    /// Page that decided to leave. Everything behind it is stopped, then it gets `Data::Halted`.
    pub halt: Option<PageId>,
    /// Something runs behind the top page that leaving stops.
    pub behind: bool,
    /// Rereads the status, since an action may have changed it.
    pub recheck: std::cell::Cell<bool>,
    pub handover: Option<Handover>,
    /// Text box cursor position this frame, for the terminal cursor.
    pub cursor: std::cell::Cell<Option<(u16, u16)>>,
    /// Background jobs under way, for the spinner.
    pending: std::cell::Cell<usize>,
    tx: Sender<Msg>,
    wake: Arc<dyn Fn() + Send + Sync>,
    page: PageId,
    pub trace: crate::trace::Trace,
}

impl Ctx {
    /// Runs a job off the drawing thread and sends its result to the calling page.
    pub fn spawn<T: Into<Data> + Send + 'static>(&self, job: impl FnOnce() -> T + Send + 'static) {
        let (tx, wake, page) = (self.tx.clone(), self.wake.clone(), self.page);
        self.pending.set(self.pending.get() + 1);
        std::thread::spawn(move || {
            let result = job();
            let _ = tx.send(Msg::Data(page, result.into()));
            wake();
        });
    }

    /// Sends script events to the calling page.
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

    pub fn busy(&self) -> bool {
        self.pending.get() > 0
    }

    /// Every required action passed. Hidden until their checks answer.
    pub fn has(&self, action: &spec::Action) -> bool {
        action.requires.is_empty() || self.offered.get(&action.id).copied().unwrap_or(false)
    }

    /// The named actions this machine has, in list order.
    pub fn rows(&self, names: &[String]) -> Vec<&'static spec::Action> {
        self.module
            .named(names)
            .into_iter()
            .filter(|a| self.has(a))
            .collect()
    }

    /// First `on_failure` action this machine has.
    pub fn fallback(&self, action: &spec::Action) -> Option<&'static spec::Action> {
        self.rows(&action.on_failure).into_iter().next()
    }

    /// Checks requirements off the drawing thread. Old results stay until replaced, so rows do not
    /// blink out.
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

    /// Reads every `value_from` off the drawing thread. A failed script leaves the value empty,
    /// like an unanswered question.
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

    /// Blocks, since a console keymap must load before the next keystroke. A failure is logged and
    /// the answer stays, as the person sees the effect.
    pub fn apply(&self, s: &Setting) -> Result<(), String> {
        let Some(shell) = &s.apply else { return Ok(()) };
        script::run(shell, &self.store.env())
            .map(|_| ())
            .inspect_err(|e| {
                crate::warn!("apply for {}: {e}", s.name);
            })
    }

    /// Reapplies every answer off the drawing thread, at start and after a profile. A failed one
    /// reverts to its default to be asked again, since nobody saw it fail.
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

    /// A failure is only logged, since an unsaved run asks again from the start.
    pub fn save(&self) {
        if let Err(e) = self.store.save() {
            crate::error!("{}: {e}", self.store.path().display());
        }
    }

    /// Fills answers into text, a bool as a word.
    pub fn expand(&self, text: &str) -> String {
        spec::text::expand(text, |name| crate::store::label(self.store.get(name)))
    }

    pub fn step(&self, name: &str, action: bool, run: spec::Shell) -> script::Step {
        script::Step {
            module: crate::i18n::t(&self.module.title),
            name: name.to_string(),
            action,
            run,
        }
    }

    /// Answers over the process environment, for a shell.
    pub fn env(&self) -> Vec<(String, String)> {
        self.store.env()
    }

    /// Leaving asks how to shut down: in a kiosk or where the module declares it.
    pub fn leaves(&self) -> bool {
        self.kiosk || self.module.leaves()
    }
}

/// Module text for a deliberate exit code: the caller's own first, then the module's.
pub fn told(module: &Module, own: &BTreeMap<i32, String>, f: &Failure) -> Option<String> {
    if !f.deliberate {
        return None;
    }
    module.told(own, f.code).map(crate::i18n::t)
}

/// Every non-ASCII character the UI can draw, in code point order.
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
    add(crate::store::DASH);
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

//! The stack of pages, what they share, and the keys no page takes.

use ratatui::Frame;
use std::sync::Arc;
use std::sync::mpsc::Sender;

use super::{Ctx, Flow, Msg, Nav, Page, PageId, Style, draw, pages};
use crate::cli::Start;
use crate::store::Store;

pub struct App {
    pages: Vec<(PageId, Box<dyn Page>)>,
    next: PageId,
    pub ctx: Ctx,
    quit: bool,
    /// Pokes the status check, so it reads again right after an action ran.
    poke: Option<Sender<()>>,
}

impl App {
    pub fn new(
        start: Start,
        dir: &std::path::Path,
        tx: Sender<Msg>,
        wake: Arc<dyn Fn() + Send + Sync>,
        console: bool,
    ) -> std::io::Result<App> {
        let mut store = Store::new(start.module, dir, start.dry_run);
        let first = !store.exists();
        store.load()?;
        crate::log::init(store.log())?;
        crate::info!(
            "{} {}",
            crate::i18n::t(&start.module.title),
            crate::version::version()
        );
        // A language the answer file keeps is settled. Otherwise nothing is translated until the
        // first page has asked, and English stands where there is nothing to ask.
        let settled = crate::i18n::matched(&store.language).is_some();
        if settled {
            crate::i18n::set(&store.language);
        } else {
            store.language = crate::i18n::SOURCE.to_string();
        }
        let product = &crate::spec::loaded().product;
        let ctx = Ctx {
            module: start.module,
            store,
            style: Style::new(product, console),
            kiosk: start.kiosk,
            status: None,
            offered: Default::default(),
            first,
            gated: false,
            presets_seen: false,
            wizard: 0,
            imported: false,
            answered: None,
            halt: false,
            recheck: Default::default(),
            cursor: Default::default(),
            handover: None,
            pending: Default::default(),
            tx,
            wake,
            page: 0,
        };
        let mut app = App {
            pages: Vec::new(),
            next: 0,
            ctx,
            quit: false,
            poke: None,
        };
        app.push(Box::new(pages::dashboard::DashboardPage::new()));
        if !settled && crate::i18n::langs().len() > 1 {
            app.push(Box::new(pages::language::LanguagePage::new()));
        }
        app.push(Box::new(pages::splash::SplashPage::new()));
        Ok(app)
    }

    /// Starts what runs beside the pages, once the first frame is on the screen: the status
    /// check, the look at which actions this machine has, the values read off it, and the
    /// answers put in force again.
    pub fn start(&mut self) {
        self.ctx.look();
        self.ctx.resolve();
        self.ctx.settle();
        let Some(status) = &crate::spec::loaded().product.status else {
            return;
        };
        let (poke, poked) = std::sync::mpsc::channel::<()>();
        self.poke = Some(poke);
        let (tx, wake, every, check) = (
            self.ctx.tx.clone(),
            self.ctx.wake.clone(),
            status.every,
            status.check.clone(),
        );
        let env = self.ctx.store.env();
        std::thread::spawn(move || {
            loop {
                let pass = crate::script::run(&check, &env).is_ok();
                if tx.send(Msg::Status(pass)).is_err() {
                    return;
                }
                wake();
                if poked.recv_timeout(every) == Err(std::sync::mpsc::RecvTimeoutError::Disconnected)
                {
                    return;
                }
            }
        });
    }

    fn push(&mut self, page: Box<dyn Page>) {
        self.next += 1;
        self.pages.push((self.next, page));
    }

    pub fn done(&self) -> bool {
        self.quit
    }

    /// When the driver wakes for a tick: on the next beat of what moves, else on the next idle one.
    pub fn wake(&self, now: std::time::Instant) -> std::time::Instant {
        let page = self.pages.last().map(|(_, p)| p);
        let pace = match page {
            Some(p) if p.animating(&self.ctx) => p.pace(),
            _ if self.ctx.busy() => super::BEAT,
            _ => super::IDLE,
        };
        super::next_beat(now, pace)
    }

    pub fn handle(&mut self, msg: Msg) {
        let top = self.pages.last().map(|(id, _)| *id).unwrap_or(0);
        let typing = self.pages.last().is_some_and(|(_, p)| p.typing());
        let msg = match msg {
            Msg::Held(key) if key.repeats(typing) => Msg::Key(key),
            Msg::Held(_) => return,
            msg => msg,
        };
        match msg {
            Msg::Key(key) => {
                self.ctx.page = top;
                let (_, page) = self.pages.last_mut().expect("the dashboard stays");
                let typing = page.typing();
                let holds = page.holds();
                let flow = match page.key(key, &mut self.ctx) {
                    Flow::Ignored => match key.nav(typing) {
                        Some(Nav::Back) if holds || self.pages.len() == 1 => self.exit(),
                        Some(Nav::Back) => Flow::Pop,
                        Some(Nav::Quit) => self.exit(),
                        _ => Flow::Stay,
                    },
                    flow => flow,
                };
                self.apply(flow);
            }
            Msg::Tick => {
                self.ctx.page = top;
                if let Some((_, page)) = self.pages.last_mut() {
                    let flow = page.tick(&mut self.ctx);
                    self.apply(flow);
                }
            }
            Msg::Resize | Msg::Held(_) => {}
            Msg::Data(id, data) => {
                self.ctx
                    .pending
                    .set(self.ctx.pending.get().saturating_sub(1));
                self.deliver(id, |page, ctx| page.data(data, ctx));
            }
            Msg::Run(id, event) => self.deliver(id, |page, ctx| page.run(event, ctx)),
            Msg::Status(pass) => self.ctx.status = Some(pass),
            Msg::Offered(id, yes) => {
                self.ctx.offered.insert(id, yes);
            }
            Msg::Resolved(name, value) => self.ctx.store.set(&name, &value),
        }
        if self.ctx.halt {
            self.ctx.halt = false;
            for (_, page) in &mut self.pages {
                page.stop();
            }
        }
        if self.ctx.recheck.replace(false)
            && let Some(poke) = &self.poke
        {
            let _ = poke.send(());
        }
    }

    /// Hands a result to the page that asked. Its next step counts only while it is on top.
    fn deliver(&mut self, id: PageId, f: impl FnOnce(&mut Box<dyn Page>, &mut Ctx) -> Flow) {
        let top = self.pages.last().map(|(i, _)| *i);
        let Some((_, page)) = self.pages.iter_mut().find(|(i, _)| *i == id) else {
            return;
        };
        self.ctx.page = id;
        let flow = f(page, &mut self.ctx);
        if top == Some(id) {
            self.apply(flow);
        }
    }

    /// The way out: where the module says how the machine is put down, or in a kiosk, a question;
    /// otherwise the program ends.
    fn exit(&mut self) -> Flow {
        if !(self.ctx.kiosk || self.ctx.module.leaves()) {
            return Flow::Quit;
        }
        if self.pages.last().is_some_and(|(_, p)| p.leaving()) {
            return Flow::Stay;
        }
        let bare = self.pages.last().is_some_and(|(_, p)| p.bare());
        Flow::Push(Box::new(pages::leave::LeavePage::new(
            &self.ctx,
            self.pages.iter().any(|(_, p)| p.holds()),
            bare,
        )))
    }

    fn apply(&mut self, flow: Flow) {
        match flow {
            Flow::Stay | Flow::Ignored => {}
            Flow::Push(page) => self.push(page),
            Flow::Replace(page) => {
                if self.pages.len() > 1 {
                    self.pages.pop();
                }
                self.push(page);
            }
            Flow::Pop => self.pop(1),
            Flow::PopN(n) => self.pop(n),
            Flow::Home => self.pop(self.pages.len().saturating_sub(1)),
            Flow::Quit => {
                for (_, page) in &mut self.pages {
                    page.stop();
                }
                self.quit = true;
            }
        }
    }

    fn pop(&mut self, n: usize) {
        for _ in 0..n {
            if self.pages.len() > 1 {
                self.pages.pop();
            }
        }
        if n > 0
            && let Some((id, page)) = self.pages.last_mut()
        {
            self.ctx.page = *id;
            let flow = page.resumed(&mut self.ctx);
            self.apply(flow);
        }
    }

    pub fn draw(&mut self, frame: &mut Frame) {
        let area = frame.area();
        // The module, then the pages from the last one the trail starts over at: a run of
        // questions is one place to stay in while the question changes, not a path.
        let from = self.pages.iter().rposition(|(_, p)| p.root()).unwrap_or(0);
        let mut path = vec![crate::i18n::t(&self.ctx.module.title)];
        path.extend(
            self.pages[from..]
                .iter()
                .filter(|(_, p)| !p.home())
                .map(|(_, p)| p.title())
                .filter(|t| !t.is_empty()),
        );
        // The note of the page in front, or of the page under it: a run's counter stands while it
        // asks.
        let note = self.pages.iter().rev().find_map(|(_, p)| p.note(&self.ctx));
        let (id, page) = self.pages.last_mut().expect("the dashboard stays");
        self.ctx.page = *id;
        self.ctx.cursor.set(None);
        if page.bare() {
            frame.buffer_mut().set_style(area, self.ctx.style.base());
            page.draw(area, frame.buffer_mut(), &mut self.ctx);
        } else {
            let content = draw::frame(area, frame.buffer_mut(), &self.ctx, &path, note);
            page.draw(content, frame.buffer_mut(), &mut self.ctx);
            let hints = page.hints(&self.ctx);
            draw::footer(area, frame.buffer_mut(), &self.ctx, &hints);
        }
        // The terminal's own cursor where a text box was drawn, hidden everywhere else.
        if let Some(at) = self.ctx.cursor.get() {
            frame.set_cursor_position(at);
        }
    }

    /// The pages' titles from the bottom, for the tests.
    #[cfg(test)]
    pub fn titles(&self) -> Vec<String> {
        self.pages.iter().map(|(_, p)| p.title()).collect()
    }

    #[cfg(test)]
    pub fn depth(&self) -> usize {
        self.pages.len()
    }
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use crate::ui::Key;
    use ratatui::Terminal;
    use ratatui::backend::TestBackend;
    use std::sync::mpsc::{Receiver, RecvTimeoutError};
    use std::time::{Duration, Instant};

    /// An app on the fixture product, in a folder of its own, its scripts runnable.
    pub fn app(dry_run: bool) -> (App, Terminal<TestBackend>, Receiver<Msg>) {
        crate::script::tests::use_fixture();
        let (tx, rx) = std::sync::mpsc::channel();
        let loaded: &'static crate::spec::Loaded = Box::leak(Box::new(
            crate::spec::load(&crate::spec::tests::fixture()).unwrap(),
        ));
        let module = loaded.module("setup").unwrap();
        let dir = std::env::temp_dir().join(format!("ui-test-{}-{}", std::process::id(), rand()));
        std::fs::create_dir_all(&dir).unwrap();
        let store = Store::new(module, &dir, dry_run);
        let ctx = Ctx {
            module,
            store,
            style: Style::new(&loaded.product, false),
            kiosk: false,
            status: None,
            offered: Default::default(),
            first: true,
            gated: true,
            presets_seen: false,
            wizard: 0,
            imported: false,
            answered: None,
            halt: false,
            recheck: Default::default(),
            cursor: Default::default(),
            handover: None,
            pending: Default::default(),
            tx,
            wake: Arc::new(|| {}),
            page: 0,
        };
        let mut app = App {
            pages: Vec::new(),
            next: 0,
            ctx,
            quit: false,
            poke: None,
        };
        app.push(Box::new(pages::dashboard::DashboardPage::new()));
        (app, Terminal::new(TestBackend::new(80, 30)).unwrap(), rx)
    }

    fn rand() -> u128 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    }

    pub fn screen(app: &mut App, term: &mut Terminal<TestBackend>) -> String {
        term.draw(|f| app.draw(f)).unwrap();
        let buf = term.backend().buffer();
        (0..buf.area.height)
            .map(|y| {
                (0..buf.area.width)
                    .map(|x| buf[(x, y)].symbol())
                    .collect::<String>()
                    .trim_end()
                    .to_string()
            })
            .collect::<Vec<_>>()
            .join("\n")
    }

    pub fn open(app: &mut App, page: Box<dyn Page>) {
        app.push(page);
    }

    pub fn press(app: &mut App, keys: &[Key]) {
        for k in keys {
            app.handle(Msg::Key(*k));
        }
    }

    pub fn type_text(app: &mut App, text: &str) {
        for c in text.chars() {
            app.handle(Msg::Key(Key::Char(c)));
        }
    }

    /// Draws, ticks and takes what the background sends, until nothing has come for a while.
    pub fn settle(app: &mut App, term: &mut Terminal<TestBackend>, rx: &Receiver<Msg>) {
        let mut quiet = Instant::now();
        loop {
            term.draw(|f| app.draw(f)).unwrap();
            app.handle(Msg::Tick);
            match rx.recv_timeout(Duration::from_millis(30)) {
                Ok(msg) => {
                    app.handle(msg);
                    quiet = Instant::now();
                }
                Err(RecvTimeoutError::Timeout) if quiet.elapsed() > Duration::from_millis(400) => {
                    return;
                }
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => return,
            }
        }
    }

    /// Where the language page leads: through the questions asked first, the starting points
    /// and the open questions to the dashboard.
    #[test]
    fn the_opening_asks_in_order_and_ends_on_the_dashboard() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        crate::i18n::set("en");
        let (mut app, mut term, rx) = app(true);
        open(&mut app, Box::new(pages::language::LanguagePage::new()));
        let shown = screen(&mut app, &mut term);
        let langs = crate::i18n::langs();
        let names: Vec<&str> = langs.iter().map(|l| l.name.as_str()).collect();
        assert!(
            shown.contains("Please choose your language")
                && shown.contains("English")
                && names.iter().all(|n| shown.contains(n)),
            "{shown}"
        );
        // English, the first row, whatever this machine speaks.
        press(&mut app, &[Key::Home, Key::Enter]);
        settle(&mut app, &mut term, &rx);
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Keyboard") && shown.contains("us") && shown.contains("de"),
            "{shown}"
        );
        assert!(
            app.titles().last().unwrap() == "Keyboard" && shown.contains("Filter"),
            "asked first, its box open: {shown}"
        );
        type_text(&mut app, "de");
        press(&mut app, &[Key::Enter]);
        assert_eq!(app.ctx.store.get("TUX_KEYMAP"), "de");
        settle(&mut app, &mut term, &rx);
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Starting point")
                && shown.contains("Desktop")
                && shown.contains("Core")
                && shown.contains("A desktop."),
            "{shown}"
        );
        press(&mut app, &[Key::Down, Key::Enter]);
        settle(&mut app, &mut term, &rx);
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Hostname") && shown.contains("tuxbox") && shown.contains("1 of 2"),
            "prefilled and counted: {shown}"
        );
        press(&mut app, &[Key::Enter]);
        settle(&mut app, &mut term, &rx);
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Disk") && shown.contains("sda 20G") && shown.contains("2 of 2"),
            "{shown}"
        );
        press(&mut app, &[Key::Enter]);
        settle(&mut app, &mut term, &rx);
        assert_eq!(app.depth(), 1, "home: {:?}", app.titles());
        let shown = screen(&mut app, &mut term);
        for text in [
            "Install now",
            "Region",
            "Keyboard",
            "de",
            "System",
            "Hostname",
            "tuxbox",
            "Desktop",
            "none",
            "Storage",
            "sda",
            "Encryption",
            "Yes",
            "Interface language",
            "English",
            "Leave a note",
            "Reset all answers",
        ] {
            assert!(shown.contains(text), "{text} missing:\n{shown}");
        }
        assert!(
            !shown.contains("Virtual machine")
                && !shown.contains("Password")
                && !shown.contains("Driver"),
            "{shown}"
        );
        assert!(
            std::fs::read_to_string(app.ctx.store.path())
                .unwrap()
                .contains("TUX_HOST='tuxbox' # Hostname")
        );
    }

    fn answered(app: &mut App) {
        for (name, value) in [
            ("TUX_KEYMAP", "us"),
            ("TUX_HOST", "tuxbox"),
            ("TUX_DESKTOP", "none"),
            ("TUX_DISK", "sda"),
        ] {
            app.ctx.store.set(name, value);
        }
        app.ctx.first = false;
    }

    #[test]
    fn the_dashboard_filters_and_opens_a_question_that_holds_an_answer_to_its_rule() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        crate::i18n::set("en");
        let (mut app, mut term, rx) = app(true);
        answered(&mut app);
        press(&mut app, &[Key::Char('f')]);
        type_text(&mut app, "host");
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Hostname") && !shown.contains("Disk") && !shown.contains("Region"),
            "{shown}"
        );
        press(&mut app, &[Key::Enter]);
        settle(&mut app, &mut term, &rx);
        assert_eq!(app.titles().last().unwrap(), "Hostname");
        press(&mut app, &[Key::Ctrl('u')]);
        type_text(&mut app, "Tux");
        press(&mut app, &[Key::Enter]);
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Lower case letters, digits and - only."),
            "{shown}"
        );
        assert_eq!(app.ctx.store.get("TUX_HOST"), "tuxbox", "not taken");
        press(&mut app, &[Key::Ctrl('u')]);
        type_text(&mut app, "tux");
        press(&mut app, &[Key::Enter]);
        assert_eq!((app.ctx.store.get("TUX_HOST"), app.depth()), ("tux", 1));
        press(&mut app, &[Key::Esc]);
        let shown = screen(&mut app, &mut term);
        assert!(shown.contains("Disk"), "the filter is closed: {shown}");
    }

    /// The start: the lists read again, the password twice, the module's question, then the run,
    /// which asks mid-run, confirms, reports and ends on what follows.
    #[test]
    fn install_now_asks_the_password_confirms_and_runs_to_the_end() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        crate::i18n::set("en");
        let (mut app, mut term, rx) = app(false);
        answered(&mut app);
        screen(&mut app, &mut term);
        press(&mut app, &[Key::Enter]);
        settle(&mut app, &mut term, &rx);
        assert_eq!(
            app.titles().last().unwrap(),
            "Password",
            "{:?}",
            app.titles()
        );
        type_text(&mut app, "pw");
        press(&mut app, &[Key::Enter]);
        assert!(screen(&mut app, &mut term).contains("Repeat"));
        type_text(&mut app, "px");
        press(&mut app, &[Key::Enter]);
        assert!(screen(&mut app, &mut term).contains("The two entries do not match."));
        type_text(&mut app, "pw");
        press(&mut app, &[Key::Enter]);
        type_text(&mut app, "pw");
        press(&mut app, &[Key::Enter]);
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Install on sda?") && shown.contains("Everything on it is erased."),
            "{shown}"
        );
        assert_eq!(app.ctx.store.get("TUX_PASSWORD"), "pw");
        press(&mut app, &[Key::Down, Key::Enter]);
        settle(&mut app, &mut term, &rx);
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Snapshot") && shown.contains("one") && shown.contains("two"),
            "asked mid-run: {shown}"
        );
        assert!(shown.contains("2 of 3"), "{shown}");
        press(&mut app, &[Key::Enter]);
        settle(&mut app, &mut term, &rx);
        let shown = screen(&mut app, &mut term);
        assert!(shown.contains("Put one in place?"), "{shown}");
        press(&mut app, &[Key::Down, Key::Enter]);
        settle(&mut app, &mut term, &rx);
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Installed") && shown.contains("tuxbox is ready."),
            "{shown}"
        );
        press(&mut app, &[Key::Enter]);
        settle(&mut app, &mut term, &rx);
        std::thread::sleep(Duration::from_millis(650));
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Finished in") && shown.contains("1 of 1 tests passed"),
            "{shown}"
        );
        assert!(
            shown.contains("Open a shell") && shown.contains("Continue"),
            "{shown}"
        );
        assert_eq!(app.ctx.store.get("TUX_PASSWORD"), "", "forgotten");
        let dir = app.ctx.store.path().parent().unwrap().to_path_buf();
        assert_eq!(
            std::fs::read_to_string(dir.join("host")).unwrap().trim(),
            "tuxbox"
        );
        press(&mut app, &[Key::Enter]);
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Restart") && shown.contains("Exit"),
            "{shown}"
        );
    }

    /// The dashboard lists its rows as the module does, a blank row under the start and under
    /// the answers.
    #[test]
    fn the_dashboard_keeps_the_modules_order() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        crate::i18n::set("en");
        let (mut app, mut term, _rx) = app(false);
        answered(&mut app);
        let shown = screen(&mut app, &mut term);
        let rows: Vec<&str> = shown
            .lines()
            .map(|l| l.trim_start_matches([' ', '▶']).trim_end())
            .skip_while(|l| !l.starts_with("Install now"))
            .collect();
        let at = |label: &str| {
            rows.iter()
                .position(|r| r.starts_with(label))
                .unwrap_or_else(|| panic!("{label} missing:\n{shown}"))
        };
        let order = [
            at("Install now"),
            at("Interface language"),
            at("Leave a note"),
            at("Region"),
            at("Reset all answers"),
        ];
        assert!(order.is_sorted(), "{order:?}\n{shown}");
        assert_eq!(rows[order[0] + 1], "", "no gap under the start:\n{shown}");
        assert_eq!(rows[order[4] - 1], "", "no gap under the answers:\n{shown}");
        assert_eq!(order[2], order[1] + 1, "a gap inside a block:\n{shown}");
    }

    /// While the tasks run, tab shows what they print: a finished line once, the line being
    /// redrawn as it stands, a long one wrapped. Tab again shows the list.
    #[test]
    fn tab_shows_what_the_running_tasks_print_and_turns_back() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        crate::i18n::set("en");
        let (mut app, mut term, _rx) = app(false);
        answered(&mut app);
        let run = Box::new(pages::run::RunPage::new(&app.ctx));
        open(&mut app, run);
        let id = app.next;
        let print = |app: &mut App, e| app.handle(Msg::Run(id, e));
        print(&mut app, crate::script::Event::Line("first".into()));
        print(&mut app, crate::script::Event::Drawn("50%".into()));
        press(&mut app, &[Key::Tab]);
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Working")
                && shown.contains("first")
                && shown.contains("50%")
                && shown.contains("tab overview"),
            "{shown}"
        );
        assert!(!shown.contains("Prepare the disk"), "{shown}");
        print(&mut app, crate::script::Event::Drawn("75%".into()));
        print(&mut app, crate::script::Event::Line("100%".into()));
        let long = format!("{}omega", "word ".repeat(30));
        print(&mut app, crate::script::Event::Line(long));
        let shown = screen(&mut app, &mut term);
        assert!(shown.contains("100%") && shown.contains("omega"), "{shown}");
        assert!(!shown.contains("50%") && !shown.contains("75%"), "{shown}");
        press(&mut app, &[Key::Tab]);
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Prepare the disk") && shown.contains("tab details"),
            "{shown}"
        );
        assert!(!shown.contains("first"), "{shown}");
    }

    /// After the run, tab shows what each task printed under its title. A key meant for the rows
    /// it hides chooses nothing.
    #[test]
    fn tab_shows_what_a_finished_run_printed_under_each_task() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        crate::i18n::set("en");
        let (mut app, mut term, rx) = app(false);
        answered(&mut app);
        let run = Box::new(pages::run::RunPage::new(&app.ctx));
        open(&mut app, run);
        settle(&mut app, &mut term, &rx);
        press(&mut app, &[Key::Enter]);
        settle(&mut app, &mut term, &rx);
        press(&mut app, &[Key::Down, Key::Enter]);
        settle(&mut app, &mut term, &rx);
        press(&mut app, &[Key::Enter]);
        settle(&mut app, &mut term, &rx);
        std::thread::sleep(Duration::from_millis(650));
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Continue") && shown.contains("tab details"),
            "{shown}"
        );
        press(&mut app, &[Key::Tab]);
        let shown = screen(&mut app, &mut term);
        let rows: Vec<&str> = shown.lines().map(str::trim).collect();
        let at = rows.iter().position(|r| *r == "Go back to a snapshot");
        assert_eq!(at.map(|at| rows[at + 1]), Some("one"), "{shown}");
        assert!(
            shown.contains("Finished in")
                && shown.contains("Install the base")
                && shown.contains("tab overview"),
            "{shown}"
        );
        assert!(!shown.contains("Continue"), "{shown}");
        press(&mut app, &[Key::Enter]);
        assert!(!app.done(), "an enter over the text chose a row");
        press(&mut app, &[Key::Tab]);
        assert!(screen(&mut app, &mut term).contains("Continue"));
    }

    #[test]
    fn a_task_that_stops_itself_is_told_in_the_modules_words_and_a_broken_one_in_full() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        crate::i18n::set("en");
        for (host, expect) in [
            ("taken", "taken is on the network already."),
            ("broken", "Install the base"),
        ] {
            let (mut app, mut term, rx) = app(false);
            answered(&mut app);
            app.ctx.store.set("TUX_HOST", host);
            app.ctx.store.set("TUX_DESKTOP", "gnome");
            app.ctx.store.set("TUX_DRIVER", "none");
            let run = Box::new(pages::run::RunPage::new(&app.ctx));
            open(&mut app, run);
            settle(&mut app, &mut term, &rx);
            press(&mut app, &[Key::Enter]);
            settle(&mut app, &mut term, &rx);
            press(&mut app, &[Key::Down, Key::Enter]);
            settle(&mut app, &mut term, &rx);
            std::thread::sleep(Duration::from_millis(650));
            let shown = screen(&mut app, &mut term);
            assert!(shown.contains(expect), "{host}: {shown}");
            if host == "broken" {
                assert!(
                    shown.contains("Failed")
                        && shown.contains("Exit code")
                        && shown.contains("Share the log")
                        && shown.contains("Back to the dashboard"),
                    "{shown}"
                );
                assert!(shown.contains("task.sh:2"), "{shown}");
            }
        }
    }

    #[test]
    fn an_optional_task_that_fails_is_counted_and_read_behind_the_results() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        crate::i18n::set("en");
        let (mut app, mut term, rx) = app(false);
        answered(&mut app);
        app.ctx.store.set("TUX_DESKTOP", "gnome");
        app.ctx.store.set("TUX_DRIVER", "none");
        let run = Box::new(pages::run::RunPage::new(&app.ctx));
        open(&mut app, run);
        settle(&mut app, &mut term, &rx);
        press(&mut app, &[Key::Enter]);
        settle(&mut app, &mut term, &rx);
        press(&mut app, &[Key::Down, Key::Enter]);
        settle(&mut app, &mut term, &rx);
        press(&mut app, &[Key::Enter]);
        settle(&mut app, &mut term, &rx);
        std::thread::sleep(Duration::from_millis(650));
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("1 of 1 optional tasks failed") && shown.contains("Test results"),
            "{shown}"
        );
        press(&mut app, &[Key::Up, Key::Up, Key::Up, Key::Enter]);
        let shown = screen(&mut app, &mut term);
        assert!(shown.contains("Install the desktop"), "{shown}");
        press(&mut app, &[Key::Enter]);
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Exit code") && shown.contains("task.sh:1"),
            "{shown}"
        );
    }

    #[test]
    fn an_action_asks_its_input_runs_and_reports() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        crate::i18n::set("en");
        let (mut app, mut term, rx) = app(false);
        answered(&mut app);
        screen(&mut app, &mut term);
        press(&mut app, &[Key::Char('f')]);
        type_text(&mut app, "note");
        press(&mut app, &[Key::Enter]);
        settle(&mut app, &mut term, &rx);
        assert_eq!(app.titles().last().unwrap(), "Note");
        type_text(&mut app, "hi");
        press(&mut app, &[Key::Enter]);
        settle(&mut app, &mut term, &rx);
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Noted") && shown.contains("hi is written down."),
            "{shown}"
        );
        press(&mut app, &[Key::Enter]);
        assert_eq!(app.depth(), 1);
    }

    /// What an action's script wrote into the answer file under a name no setting has reaches
    /// its report: the address, as writing and as a code.
    #[test]
    fn an_actions_answer_reaches_its_report_as_a_code() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        crate::i18n::set("en");
        let (mut app, mut term, rx) = app(true);
        answered(&mut app);
        let share = app
            .ctx
            .module
            .actions
            .iter()
            .find(|a| a.id == "share")
            .unwrap();
        let flow = pages::action::open(&mut app.ctx, share, false);
        app.apply(flow);
        settle(&mut app, &mut term, &rx);
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Shared") && shown.contains("https://x/1") && shown.contains("█▀▀▀▀▀█"),
            "{shown}"
        );
    }

    /// Leaving from the first page, before there is a frame: the way out looks like that page,
    /// and esc has nowhere to go back to.
    #[test]
    fn leaving_from_the_first_page_stays_bare() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        crate::i18n::set("en");
        let (mut app, mut term, _) = app(true);
        open(&mut app, Box::new(pages::language::LanguagePage::new()));
        press(&mut app, &[Key::Esc]);
        assert_eq!(
            app.titles().last().unwrap(),
            "",
            "esc stays on the first page"
        );
        press(&mut app, &[Key::Char('q')]);
        assert_eq!(app.titles().last().unwrap(), "Leave");
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Restart")
                && shown.contains("Exit")
                && shown.contains("move")
                && !shown.contains('\u{203a}'),
            "{shown}"
        );
        press(&mut app, &[Key::Esc]);
        assert_eq!(app.titles().last().unwrap(), "");
    }

    /// A language the answer file keeps is the language, and the first page is not asked.
    #[test]
    fn a_kept_language_skips_the_first_page() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let module = crate::spec::loaded().modules.first().unwrap();
        let depth = |conf: Option<&str>| {
            let dir =
                std::env::temp_dir().join(format!("app-new-{}-{}", std::process::id(), rand()));
            std::fs::create_dir_all(&dir).unwrap();
            if let Some(conf) = conf {
                std::fs::write(dir.join(format!("{}.conf", module.id)), conf).unwrap();
            }
            let (tx, _rx) = std::sync::mpsc::channel();
            let start = Start {
                module,
                dry_run: true,
                kiosk: false,
            };
            App::new(start, &dir, tx, Arc::new(|| {}), false)
                .unwrap()
                .depth()
        };
        let asked = if crate::i18n::langs().len() > 1 { 3 } else { 2 };
        assert_eq!(
            depth(None),
            asked,
            "the dashboard, the first page, the wordmark"
        );
        assert_eq!(
            depth(Some("MODULE_LANGUAGE='en'\n")),
            2,
            "the dashboard and the wordmark"
        );
    }

    /// The row under the cursor lies on the surface, from the margin to the right edge.
    #[test]
    fn the_row_under_the_cursor_lies_on_the_surface() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        crate::i18n::set("en");
        let (mut app, mut term, _) = app(true);
        answered(&mut app);
        let shown = screen(&mut app, &mut term);
        let (y, line) = shown
            .lines()
            .enumerate()
            .find(|(_, l)| l.contains("Install now"))
            .expect("the start row");
        let x = line.find("Install now").unwrap() as u16;
        let buffer = term.backend().buffer();
        let selection = app.ctx.style.selection;
        assert_eq!(buffer[(x, y as u16)].bg, selection, "under the label");
        assert_eq!(buffer[(x - 2, y as u16)].bg, selection, "under the cursor");
        assert_eq!(
            buffer[(line.len() as u16 - 6, y as u16)].bg,
            selection,
            "to the edge"
        );
        let under = line.find("Username").map(|_| y + 2).unwrap_or(y + 2) as u16;
        assert_ne!(buffer[(x, under)].bg, selection, "one row only");
    }

    /// Typing shows the terminal's own cursor, after the text.
    #[test]
    fn typing_puts_the_terminals_cursor_after_the_text() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        crate::i18n::set("en");
        let (mut app, mut term, _) = app(true);
        answered(&mut app);
        screen(&mut app, &mut term);
        press(&mut app, &[Key::Char('f')]);
        type_text(&mut app, "Dis");
        let shown = screen(&mut app, &mut term);
        let at = term.get_cursor_position().unwrap();
        let line = shown.lines().nth(at.y as usize).unwrap();
        assert_eq!(
            line.find("Dis").map(|i| line[..i].chars().count() + 3),
            Some(at.x as usize),
            "the cursor stands after what was typed: {line}"
        );
    }

    #[test]
    fn a_report_draws_a_code_beside_its_words() {
        let (mut app, mut term, _) = app(true);
        open(
            &mut app,
            Box::new(pages::report::ReportPage::new(
                "Shared".into(),
                "Log shared\n\nScan the code.".into(),
                Some("https://paste.rs/abc".into()),
                false,
                pages::report::Close::PopN(1),
            )),
        );
        let shown = screen(&mut app, &mut term);
        assert!(
            shown.contains("Log shared")
                && shown.contains("https://paste.rs/abc")
                && shown.contains("█▀▀▀▀▀█"),
            "{shown}"
        );
        let mut narrow = Terminal::new(TestBackend::new(40, 20)).unwrap();
        let shown = screen(&mut app, &mut narrow);
        assert!(
            shown.contains("Log shared") && !shown.contains("█▀▀▀▀▀█"),
            "no room for a code: {shown}"
        );
    }

    /// Every page, each as something opens it.
    fn every_page(app: &App) -> Vec<Box<dyn Page>> {
        let module = app.ctx.module;
        let f = crate::script::Failure {
            unit: "Install the base".into(),
            script: "setup/tasks/install/base/task.sh".into(),
            line: 2,
            code: 1,
            command: "false".into(),
            stderr: "boom".into(),
            ..Default::default()
        };
        vec![
            Box::new(pages::dashboard::DashboardPage::new()),
            Box::new(pages::language::LanguagePage::new()),
            Box::new(pages::language::LangPage::new(pages::Then::Pop)),
            Box::new(pages::splash::SplashPage::after(100)),
            Box::new(pages::splash::SplashPage::after(2000)),
            Box::new(pages::question::QuestionPage::setting(
                module.setting("TUX_HOST").unwrap(),
                pages::Then::Pop,
            )),
            Box::new(pages::password::PasswordPage::new(
                module.setting("TUX_PASSWORD").unwrap(),
                pages::Then::Pop,
            )),
            Box::new(pages::gate::GatePage::new()),
            Box::new(pages::presets::PresetsPage::new()),
            Box::new(pages::confirm::YesNoPage::reset()),
            Box::new(pages::report::ReportPage::new(
                "R".into(),
                "Done\n\nAll of it.".into(),
                Some("https://x".into()),
                true,
                pages::report::Close::PopN(1),
            )),
            Box::new(pages::failure::FailurePage::new(
                "F".into(),
                Some("It said no.".into()),
                f.clone(),
                vec![crate::ui::detail::Act::new("Back", |_| Flow::Pop)],
            )),
            Box::new(pages::results::ResultsPage::new(
                "1 of 2 tests passed".into(),
                vec![("Install the base".into(), f)],
            )),
            Box::new(pages::leave::LeavePage::new(&app.ctx, true, false)),
            Box::new(pages::run::RunPage::new(&app.ctx)),
        ]
    }

    /// A terminal can be made as small as one cell. No page may panic in it.
    #[test]
    fn every_page_draws_at_any_size() {
        let (mut app, _, _) = app(true);
        answered(&mut app);
        for (w, h) in [
            (1, 1),
            (2, 2),
            (8, 3),
            (20, 5),
            (39, 8),
            (120, 2),
            (3, 60),
            (80, 24),
        ] {
            let mut term = Terminal::new(TestBackend::new(w, h)).unwrap();
            for page in every_page(&app) {
                app.pages.truncate(1);
                app.push(page);
                screen(&mut app, &mut term);
            }
        }
    }

    /// The console's font has letters and codepage 437. Every page draws it those only.
    #[test]
    fn every_page_keeps_to_the_consoles_glyphs() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        crate::i18n::set("en");
        let (mut app, mut term, _) = app(true);
        answered(&mut app);
        app.ctx.style = Style::new(&crate::spec::loaded().product, true);
        let allowed = crate::ui::glyphs();
        for page in every_page(&app) {
            app.pages.truncate(1);
            app.push(page);
            let shown = screen(&mut app, &mut term);
            let foreign: String = shown
                .chars()
                .filter(|c| !c.is_ascii() && !c.is_alphabetic() && !allowed.contains(*c))
                .collect();
            assert!(foreign.is_empty(), "{foreign:?} in\n{shown}");
        }
    }

    /// Not a check: the real product on a dry run, for a look at the pages.
    /// `cargo test preview -- --ignored --nocapture`
    #[test]
    #[ignore]
    fn preview() {
        let dir = std::env::temp_dir().join("arch-os-preview");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        std::env::set_current_dir(&dir).unwrap();
        let module = crate::spec::loaded()
            .module(&std::env::var("PREVIEW_MODULE").unwrap_or("installer".into()))
            .unwrap();
        // A language kept with the answers skips the first page.
        if let Ok(code) = std::env::var("PREVIEW_LANGUAGE") {
            std::fs::write(
                dir.join(format!("{}.conf", module.id)),
                format!("MODULE_LANGUAGE='{code}'\n"),
            )
            .unwrap();
        }
        let (tx, rx) = std::sync::mpsc::channel();
        let mut app = App::new(
            Start {
                module,
                dry_run: true,
                kiosk: false,
            },
            &dir,
            tx,
            Arc::new(|| {}),
            std::env::var("PREVIEW_CONSOLE").is_ok(),
        )
        .unwrap();
        app.start();
        let mut term = Terminal::new(TestBackend::new(95, 25)).unwrap();
        let keys = std::env::var("PREVIEW_KEYS").unwrap_or_default();
        for step in std::iter::once("").chain(keys.split(',')) {
            for key in step.split(' ').filter(|k| !k.is_empty()) {
                let k = match key {
                    "enter" => Key::Enter,
                    "esc" => Key::Esc,
                    "down" => Key::Down,
                    "up" => Key::Up,
                    "f" => Key::Char('f'),
                    "q" => Key::Char('q'),
                    word => {
                        type_text(&mut app, word);
                        continue;
                    }
                };
                app.handle(Msg::Key(k));
            }
            std::thread::sleep(Duration::from_millis(2000));
            settle(&mut app, &mut term, &rx);
            println!("{}\n{}", "=".repeat(95), screen(&mut app, &mut term));
        }
    }
}

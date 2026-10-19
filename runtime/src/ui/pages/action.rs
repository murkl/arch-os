//! An action somebody opened: its inputs, a page each, its confirmation, then its script, and
//! what it has to report. Where it says no, what it falls back on opens over its pages.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use super::Then;
use super::confirm::{Outcome, YesNoPage};
use super::report::{Close, ReportPage};
use crate::i18n::t;
use crate::script::{self, Event, Failure, Session};
use crate::spec::Action;
use crate::ui::detail::Act;
use crate::ui::draw::waiting;
use crate::ui::{Ctx, Data, Flow, Key, Page};

/// Opens an action: its first page.
pub fn open(ctx: &mut Ctx, action: &'static Action, fetches: bool) -> Flow {
    crate::info!("action {}", action.id);
    Flow::Push(page(ctx, action, 0, 0, fetches))
}

/// The action's page from its `next` input on, each pushed onto the one before, and its work once
/// none is left. `depth` counts the pages before it, so the work knows how many to take away.
pub fn page(
    ctx: &Ctx,
    action: &'static Action,
    next: usize,
    depth: usize,
    fetches: bool,
) -> Box<dyn Page> {
    let mut i = next;
    while i < action.inputs.len() && !action.inputs[i].applies(ctx.store.getter()) {
        i += 1;
    }
    if let Some(input) = action.inputs.get(i) {
        let then = Then::Action {
            action,
            next: i + 1,
            depth: depth + 1,
            fetches,
        };
        if input.kind.secret() {
            return Box::new(super::password::PasswordPage::new(input, then));
        }
        return Box::new(super::question::QuestionPage::setting(input, then));
    }
    if let Some(confirm) = &action.confirm {
        let outcome = Outcome::Action {
            action,
            depth: depth + 1,
            fetches,
        };
        return Box::new(YesNoPage::new(
            t(&action.title),
            &ctx.expand(&t(confirm)),
            false,
            outcome,
        ));
    }
    Box::new(ActionPage::new(action, depth + 1, fetches))
}

pub struct ActionPage {
    action: &'static Action,
    /// The pages that go once it has worked, this one included.
    depth: usize,
    /// It fetches a profile, which the page below reads back.
    fetches: bool,
    started: bool,
    session: Option<Session>,
    /// Simulated, or run on the terminal: the outcome waits for the next tick.
    outcome: Option<Result<(), Failure>>,
}

impl ActionPage {
    pub fn new(action: &'static Action, depth: usize, fetches: bool) -> ActionPage {
        ActionPage {
            action,
            depth,
            fetches,
            started: false,
            session: None,
            outcome: None,
        }
    }

    fn start(&mut self, ctx: &mut Ctx) {
        self.started = true;
        let step = ctx.step(&t(&self.action.title), true, self.action.run.clone());
        let env = ctx.env();
        if ctx.store.dry_run() && !self.action.simulates {
            crate::info!("action {}: simulated", self.action.id);
            self.outcome = Some(Ok(()));
        } else if self.action.tty {
            // The interface stands down for the length of this one.
            ctx.handover = Some(Box::new(move || script::handover(&step, &env)));
        } else {
            match script::start(step, &env, ctx.run_sink()) {
                Ok(session) => self.session = Some(session),
                Err(e) => {
                    self.outcome = Some(Err(Failure::new(
                        &ctx.step(&t(&self.action.title), true, self.action.run.clone()),
                        e,
                    )))
                }
            }
        }
    }

    /// Once it worked it goes back with the pages before it, or to its report. Where it did not,
    /// what it falls back on opens in its place, else the failure page.
    fn proceed(&mut self, result: Result<(), Failure>, ctx: &mut Ctx) -> Flow {
        // Whatever the pages were given is gone the moment it is used, whether it worked or not.
        ctx.store.forget();
        self.session = None;
        match result {
            Ok(()) => {
                crate::info!("action {}: done", self.action.id);
                ctx.recheck.set(true);
                if self.fetches {
                    ctx.imported = true;
                }
                let Some(report) = &self.action.report else {
                    return Flow::PopN(self.depth);
                };
                // A report shows what the script wrote down, so the answer file is read back
                // first: the settings into the store, the code's value from the file alone.
                if let Err(e) = ctx.store.load() {
                    crate::warn!("{}: {e}", ctx.store.path().display());
                }
                let qr = self
                    .action
                    .qr
                    .as_ref()
                    .and_then(|q| ctx.store.read(q))
                    .filter(|v| !v.is_empty());
                Flow::Replace(Box::new(ReportPage::new(
                    t(&self.action.title),
                    ctx.expand(&t(report)),
                    qr,
                    false,
                    Close::PopN(self.depth),
                )))
            }
            Err(f) => {
                crate::error!("{f}");
                if let Some(words) = crate::ui::told(ctx.module, &self.action.errors, &f) {
                    return Flow::Replace(Box::new(ReportPage::new(
                        t(&self.action.title),
                        ctx.expand(&words),
                        None,
                        true,
                        Close::PopN(self.depth),
                    )));
                }
                if let Some(fallback) = ctx.fallback(self.action) {
                    crate::info!("action {}: opens {}", self.action.id, fallback.id);
                    return Flow::Replace(page(ctx, fallback, 0, self.depth - 1, self.fetches));
                }
                let said = self.action.error.as_ref().map(|e| ctx.expand(&t(e)));
                let depth = self.depth;
                let acts = vec![Act::new(t("Back"), move |_| Flow::PopN(depth))];
                Flow::Replace(Box::new(super::failure::FailurePage::new(
                    t(&self.action.title),
                    said,
                    f,
                    acts,
                )))
            }
        }
    }
}

impl Page for ActionPage {
    fn title(&self) -> String {
        t(&self.action.title)
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        if !self.started {
            self.start(ctx);
        }
        waiting(buf, area, &t(&self.action.title), None, ctx);
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, String)> {
        Vec::new()
    }

    fn key(&mut self, key: Key, _: &mut Ctx) -> Flow {
        match key {
            Key::Ctrl('c') => Flow::Ignored,
            _ => Flow::Stay,
        }
    }

    fn run(&mut self, event: Event, _: &mut Ctx) -> Flow {
        if let Event::Exit(result) = event {
            self.outcome = Some(result);
        }
        Flow::Stay
    }

    fn data(&mut self, data: Data, _: &mut Ctx) -> Flow {
        if let Data::Done(result) = data {
            self.outcome = Some(result.map_err(|f| *f));
        }
        Flow::Stay
    }

    fn tick(&mut self, ctx: &mut Ctx) -> Flow {
        match self.outcome.take() {
            Some(result) => self.proceed(result, ctx),
            None => Flow::Stay,
        }
    }

    fn holds(&self) -> bool {
        true
    }

    fn stop(&mut self, _: &mut Ctx) -> Option<Session> {
        self.session.take()
    }

    fn animating(&self, _: &Ctx) -> bool {
        true
    }
}

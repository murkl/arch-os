//! Opened action: a page per input, confirmation, script run and report. On failure its
//! fallback opens over its pages.

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
use crate::ui::{Ctx, Data, Does, Flow, Key, Page};

pub fn open(ctx: &mut Ctx, action: &'static Action, fetches: bool) -> Flow {
    crate::info!("action {}", action.id);
    Flow::Push(page(ctx, action, 0, 0, fetches))
}

/// Page of input `next`, each pushed on the one before, then the run. `depth` counts the pages
/// before, so the run knows how many to pop.
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
            format!("confirm {}", action.id),
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
    /// Pages to pop on success, this one included.
    depth: usize,
    /// Fetches a profile for the page below to read back.
    fetches: bool,
    started: bool,
    session: Option<Session>,
    /// Result of a simulated or terminal run, applied on the next tick.
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
            // The UI yields the terminal while this step runs.
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

    /// Success pops its pages or opens the report. Failure opens the fallback in its place, else
    /// the failure page.
    fn proceed(&mut self, result: Result<(), Failure>, ctx: &mut Ctx) -> Flow {
        // Typed inputs are forgotten right after use, success or not.
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
                // The report shows what the script wrote, so the answer file is reloaded first:
                // settings into the store, the code's value from the file only.
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
                    format!("report {}", self.action.id),
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
                        format!("stopped {}", self.action.id),
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
                let acts = vec![Act::new(t("Back"), move |_| Flow::PopN(depth)).does(Does::Back)];
                Flow::Replace(Box::new(super::failure::FailurePage::new(
                    format!("failure {}", self.action.id),
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

    fn id(&self, _: &Ctx) -> String {
        format!("action {}", self.action.id)
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        if !self.started {
            self.start(ctx);
        }
        waiting(buf, area, &t(&self.action.title), None, ctx);
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, Does)> {
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

//! Yes or no, in a sentence that says what it does. It opens on No, since an enter meant for the
//! page before must not land here.

use crate::spec::Action;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use crate::i18n::t;
use crate::ui::detail::{Block, Detail, words};
use crate::ui::list::{List, Picked, Row};
use crate::ui::{Ctx, Flow, Key, Page, Tone};

/// What a yes does.
pub enum Outcome {
    /// The run of the module: yes starts it, no forgets the passwords and goes home.
    Start,
    /// The page that asked reads the answer and goes on.
    Answer,
    /// An action's work, after its inputs: yes replaces this page with the run of its script.
    Action {
        action: &'static Action,
        depth: usize,
        fetches: bool,
    },
    /// Every answer goes.
    Reset,
    /// The page a run stopped on is left for the dashboard.
    Home,
}

pub struct YesNoPage {
    title: String,
    detail: Detail,
    list: List<bool>,
    outcome: Outcome,
}

impl YesNoPage {
    pub fn new(title: String, text: &str, yes: bool, outcome: Outcome) -> YesNoPage {
        let mut detail = Detail::default();
        detail.set(words(text), Vec::new());
        let list = List::new(vec![Row::new(false, t("No")), Row::new(true, t("Yes"))]);
        let mut page = YesNoPage {
            title,
            detail,
            list,
            outcome,
        };
        page.list.focus(&yes);
        page
    }

    /// The module's own question before its work.
    pub fn start(ctx: &Ctx, text: &str) -> YesNoPage {
        YesNoPage::new(
            t(&ctx.module.start),
            &ctx.expand(&t(text)),
            false,
            Outcome::Start,
        )
    }

    /// A question a page puts, read back from `ctx.answered`.
    pub fn ask(title: String, text: &str, yes: bool) -> YesNoPage {
        YesNoPage::new(title, text, yes, Outcome::Answer)
    }

    pub fn reset() -> YesNoPage {
        YesNoPage::new(
            t("Reset all answers"),
            &format!(
                "{}\n\n{}",
                t("Reset all answers?"),
                t(
                    "Every answer is forgotten and the file they are kept in is deleted. It starts over at the first question."
                )
            ),
            false,
            Outcome::Reset,
        )
    }

    /// Leaving a failed run for the dashboard, which offers nothing about the failure any more.
    pub fn home() -> YesNoPage {
        YesNoPage::new(
            t("Back to the dashboard"),
            &format!(
                "{}\n\n{}",
                t("Back to the dashboard?"),
                t("The failure and what this page offers are gone from the screen. The log stays.")
            ),
            false,
            Outcome::Home,
        )
    }

    fn chosen(&mut self, yes: bool, ctx: &mut Ctx) -> Flow {
        match &self.outcome {
            Outcome::Start if yes => Flow::Replace(Box::new(super::run::RunPage::new(ctx))),
            Outcome::Start => {
                ctx.store.forget();
                Flow::Home
            }
            Outcome::Answer => {
                ctx.answered = Some(yes);
                Flow::Pop
            }
            Outcome::Action {
                action,
                depth,
                fetches,
            } if yes => Flow::Replace(Box::new(super::action::ActionPage::new(
                action, *depth, *fetches,
            ))),
            Outcome::Action { depth, .. } => {
                ctx.store.forget();
                Flow::PopN(*depth)
            }
            Outcome::Reset if yes => {
                if let Err(e) = ctx.store.reset() {
                    crate::error!("{}: {e}", ctx.store.path().display());
                }
                crate::info!("every answer reset");
                ctx.first = true;
                ctx.presets_seen = false;
                ctx.wizard = 0;
                match super::next(ctx) {
                    Flow::Push(page) => Flow::Replace(page),
                    flow => flow,
                }
            }
            Outcome::Reset => Flow::Pop,
            Outcome::Home if yes => Flow::Home,
            Outcome::Home => Flow::Pop,
        }
    }
}

impl Page for YesNoPage {
    fn title(&self) -> String {
        self.title.clone()
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        // The answers right under the question, not at the foot of the page.
        let text = self
            .detail
            .height(area.width, ctx)
            .min(area.height.saturating_sub(3));
        self.detail
            .draw(Rect::new(area.x, area.y, area.width, text), buf, ctx);
        self.list.draw(
            Rect::new(area.x, area.y + text + 1, area.width, 2),
            buf,
            ctx,
        );
        let _ = Block::Blank;
        let _ = Tone::Normal;
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, String)> {
        vec![("↑↓", t("choose")), ("⏎", t("confirm")), ("esc", t("back"))]
    }

    fn root(&self) -> bool {
        matches!(self.outcome, Outcome::Start)
    }

    fn key(&mut self, key: Key, ctx: &mut Ctx) -> Flow {
        match self.list.key(key) {
            Picked::Open(yes) => self.chosen(yes, ctx),
            Picked::Used => Flow::Stay,
            Picked::Ignored if matches!(key, Key::Esc | Key::Backspace) => self.chosen(false, ctx),
            Picked::Ignored => Flow::Ignored,
        }
    }
}

//! Yes or no page. Opens on No, so an enter meant for the page before does not confirm.

use crate::spec::Action;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use crate::i18n::t;
use crate::ui::detail::{Block, Detail, words};
use crate::ui::list::{List, Picked, Row};
use crate::ui::{Ctx, Does, Flow, Key, Page, Tone};

/// What a yes does.
pub enum Outcome {
    /// Module run: yes starts it, no forgets the passwords and returns to the dashboard.
    Start,
    /// The asking page reads the answer.
    Answer,
    /// Action after its inputs: yes replaces this page with its script run.
    Action {
        action: &'static Action,
        depth: usize,
        fetches: bool,
    },
    /// Clears every answer.
    Reset,
    /// Leaves a stopped run for the dashboard.
    Home,
}

pub struct YesNoPage {
    id: String,
    title: String,
    detail: Detail,
    list: List<bool>,
    outcome: Outcome,
}

impl YesNoPage {
    pub fn new(id: String, title: String, text: &str, yes: bool, outcome: Outcome) -> YesNoPage {
        let mut detail = Detail::default();
        detail.set(words(text), Vec::new());
        let list = List::new(vec![Row::new(false, t("No")), Row::new(true, t("Yes"))]);
        let mut page = YesNoPage {
            id,
            title,
            detail,
            list,
            outcome,
        };
        page.list.focus(&yes);
        page
    }

    /// The module's question before its run.
    pub fn start(ctx: &Ctx, text: &str) -> YesNoPage {
        YesNoPage::new(
            "confirm".into(),
            t(&ctx.module.start),
            &ctx.expand(&t(text)),
            false,
            Outcome::Start,
        )
    }

    /// Question of a page, answered through `ctx.answered`.
    pub fn ask(id: String, title: String, text: &str, yes: bool) -> YesNoPage {
        YesNoPage::new(id, title, text, yes, Outcome::Answer)
    }

    pub fn reset() -> YesNoPage {
        YesNoPage::new(
            "confirm reset".into(),
            t("Reset all answers"),
            &format!(
                "{}\n\n{}",
                t("Reset all answers?"),
                t("Deletes all answers and their file, then starts at the first question.")
            ),
            false,
            Outcome::Reset,
        )
    }

    /// Leaves a failed run for the dashboard, which does not show the failure.
    pub fn home() -> YesNoPage {
        YesNoPage::new(
            "confirm home".into(),
            t("Back to the main menu"),
            &format!(
                "{}\n\n{}",
                t("Back to the main menu?"),
                t("The error is dismissed. The log is kept.")
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
    /// Yes, since an unattended start consents to everything.
    fn unattended(&mut self, ctx: &mut Ctx) -> Result<Flow, String> {
        Ok(self.chosen(true, ctx))
    }

    fn title(&self) -> String {
        self.title.clone()
    }

    fn id(&self, _: &Ctx) -> String {
        self.id.clone()
    }

    fn focus(&self) -> Option<String> {
        let yes = self.list.selected()?.id?;
        Some(if yes { "yes" } else { "no" }.into())
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        // Answers right under the question, not at the page foot.
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

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, Does)> {
        vec![
            ("↑↓", Does::Choose),
            ("⏎", Does::Answer),
            ("esc", Does::Back),
        ]
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

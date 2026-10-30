//! Failed optional tasks and failed tests of a finished run. Each row opens the failure like a
//! stopped run's.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use crate::i18n::t;
use crate::script::Failure;
use crate::ui::detail::Act;
use crate::ui::draw::put;
use crate::ui::list::{List, Picked, Row};
use crate::ui::{Ctx, Does, Flow, Key, Page, Tone};

pub struct ResultsPage {
    /// Failure count out of the total: three of four differs from three of forty.
    verdict: String,
    /// Title, the module's text for a chosen status, and the failure.
    failed: Vec<(String, Option<String>, Failure)>,
    list: List<usize>,
}

impl ResultsPage {
    pub fn new(verdict: String, failed: Vec<(String, Option<String>, Failure)>) -> ResultsPage {
        let list = List::new(
            failed
                .iter()
                .enumerate()
                .map(|(i, (title, ..))| Row::new(i, title.clone()))
                .collect(),
        );
        ResultsPage {
            verdict,
            failed,
            list,
        }
    }
}

impl Page for ResultsPage {
    fn title(&self) -> String {
        t("Test results")
    }

    fn id(&self, _: &Ctx) -> String {
        "results".into()
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        let s = ctx.style;
        put(buf, area.x, area.y, s.glyphs.fail, 1, s.tone(Tone::Error));
        put(
            buf,
            area.x + 2,
            area.y,
            &self.verdict,
            area.width.saturating_sub(2),
            s.bold(Tone::Normal),
        );
        self.list.draw(
            Rect::new(
                area.x,
                area.y + 2,
                area.width,
                area.height.saturating_sub(2),
            ),
            buf,
            ctx,
        );
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, Does)> {
        vec![("↑↓", Does::Choose), ("⏎", Does::Open), ("esc", Does::Back)]
    }

    fn key(&mut self, key: Key, _: &mut Ctx) -> Flow {
        match self.list.key(key) {
            Picked::Open(i) => {
                let (title, said, f) = &self.failed[i];
                let acts = vec![Act::new(t("Back"), |_| Flow::Pop).does(Does::Back)];
                Flow::Push(Box::new(super::failure::FailurePage::new(
                    format!("result {i}"),
                    title.clone(),
                    said.clone(),
                    f.clone(),
                    acts,
                )))
            }
            Picked::Used => Flow::Stay,
            Picked::Ignored => Flow::Ignored,
        }
    }
}

//! Failure page titled by what failed: location, tool output, log path and the module's rows
//! for it.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use crate::script::Failure;
use crate::ui::detail::{Act, Block, Detail, failure};
use crate::ui::list::Lead;
use crate::ui::{Ctx, Does, Flow, Key, Page, Tone};

pub struct FailurePage {
    id: String,
    title: String,
    detail: Detail,
}

impl FailurePage {
    /// `said` is the module's text for the failure, above the details.
    pub fn new(
        id: String,
        title: String,
        said: Option<String>,
        f: Failure,
        acts: Vec<Act>,
    ) -> FailurePage {
        let mut blocks = Vec::new();
        if let Some(said) = said {
            blocks.push(Block::Note(
                Lead::Glyph("\0", Tone::Error),
                said,
                Tone::Normal,
            ));
            blocks.push(Block::Blank);
        }
        blocks.extend(failure(&f));
        let mut detail = Detail::default();
        detail.set(blocks, acts);
        FailurePage { id, title, detail }
    }
}

impl Page for FailurePage {
    fn title(&self) -> String {
        self.title.clone()
    }

    fn id(&self, _: &Ctx) -> String {
        self.id.clone()
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        // The mark before the module's text comes from the style, known only at draw time.
        for block in &mut self.detail.body {
            if let Block::Note(Lead::Glyph(glyph, tone), _, _) = block
                && *glyph == "\0"
            {
                *glyph = ctx.style.glyphs.fail;
                *tone = Tone::Error;
            }
        }
        self.detail.draw(area, buf, ctx);
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, Does)> {
        self.detail.hints()
    }

    fn key(&mut self, key: Key, ctx: &mut Ctx) -> Flow {
        self.detail.key(key, ctx)
    }
}

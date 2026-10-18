//! One failure in full, under the name of what it happened to: where exactly, what the tool said,
//! where the log is, and the rows a module offers for it.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use crate::script::Failure;
use crate::ui::detail::{Act, Block, Detail, failure};
use crate::ui::list::Lead;
use crate::ui::{Ctx, Flow, Key, Page, Tone};

pub struct FailurePage {
    title: String,
    detail: Detail,
}

impl FailurePage {
    /// `said` is what the failure means in the module's own words, over the report.
    pub fn new(title: String, said: Option<String>, f: Failure, acts: Vec<Act>) -> FailurePage {
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
        FailurePage { title, detail }
    }
}

impl Page for FailurePage {
    fn title(&self) -> String {
        self.title.clone()
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        // The mark in front of the module's words is the style's, which only the frame knows.
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

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, String)> {
        self.detail.hints()
    }

    fn key(&mut self, key: Key, ctx: &mut Ctx) -> Flow {
        self.detail.key(key, ctx)
    }
}

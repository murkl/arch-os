//! Report page of a run or action, on success with text or on failure. The module gives the
//! text, the runtime the mark.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use crate::ui::detail::{Block, Detail, mark, words};
use crate::ui::{Ctx, Does, Flow, Key, Page, Tone};

/// Where the page leads once read.
pub enum Close {
    PopN(usize),
}

pub struct ReportPage {
    id: String,
    title: String,
    text: String,
    /// One line under the text, such as a run's tally of optional tasks and tests.
    note: Option<(String, Tone)>,
    stopped: bool,
    close: Close,
    detail: Detail,
}

impl ReportPage {
    pub fn new(id: String, title: String, text: String, stopped: bool, close: Close) -> ReportPage {
        ReportPage {
            id,
            title,
            text,
            note: None,
            stopped,
            close,
            detail: Detail::default(),
        }
    }

    pub fn noted(mut self, note: Option<(String, Tone)>) -> ReportPage {
        self.note = note;
        self
    }

    fn blocks(&self) -> Vec<Block> {
        let mut b = vec![mark(self.stopped), Block::Blank];
        b.extend(words(&self.text));
        if let Some((note, tone)) = &self.note {
            b.push(Block::Blank);
            b.push(Block::Text(note.clone(), *tone));
        }
        b
    }
}

impl Page for ReportPage {
    /// Closes at once. Unattended, the log is the reader.
    fn unattended(&mut self, _: &mut Ctx) -> Result<Flow, String> {
        Ok(match &self.close {
            Close::PopN(n) => Flow::PopN(*n),
        })
    }

    fn title(&self) -> String {
        self.title.clone()
    }

    fn id(&self, _: &Ctx) -> String {
        self.id.clone()
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        self.detail.set(self.blocks(), Vec::new());
        self.detail.draw(area, buf, ctx);
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, Does)> {
        vec![("⏎", Does::Continue)]
    }

    fn key(&mut self, key: Key, ctx: &mut Ctx) -> Flow {
        match key {
            Key::Enter | Key::Esc => match &self.close {
                Close::PopN(n) => Flow::PopN(*n),
            },
            Key::Ctrl('c') => Flow::Ignored,
            _ => self.detail.key(key, ctx),
        }
    }

    fn holds(&self) -> bool {
        true
    }
}

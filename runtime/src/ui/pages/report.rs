//! The page a run or an action holds still on when it has something to say, or when it could not
//! go on: one page in two colors. The words are the module's, the mark and the code the runtime's.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use crate::i18n::t;
use crate::ui::detail::{Block, Detail, mark, words};
use crate::ui::draw::put;
use crate::ui::{Ctx, Flow, Key, Page, Tone, qr};

/// Where the page leads once it has been read: the pages before it go.
pub enum Close {
    PopN(usize),
}

pub struct ReportPage {
    title: String,
    text: String,
    /// A value drawn to be scanned, and printed under the words as itself.
    qr: Option<String>,
    /// One line under the words: what a run has proved about itself.
    note: Option<(String, Tone)>,
    stopped: bool,
    close: Close,
    detail: Detail,
}

/// The narrowest the words may be squeezed to before the code is dropped instead.
const WORDS_MIN: u16 = 34;
const GAP: u16 = 3;

impl ReportPage {
    pub fn new(
        title: String,
        text: String,
        qr: Option<String>,
        stopped: bool,
        close: Close,
    ) -> ReportPage {
        ReportPage {
            title,
            text,
            qr,
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
        if let Some(value) = &self.qr {
            b.push(Block::Blank);
            b.push(Block::Text(value.clone(), Tone::Accent));
        }
        b
    }
}

impl Page for ReportPage {
    fn title(&self) -> String {
        self.title.clone()
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        self.detail.set(self.blocks(), Vec::new());
        // The words the major part and the code the minor, side by side: a code under a
        // paragraph wants more rows than a frame has.
        let code = self.qr.as_deref().and_then(|v| {
            qr::code(
                v,
                area.width.saturating_sub(WORDS_MIN + GAP) as usize,
                area.height as usize,
            )
        });
        let Some(code) = code else {
            self.detail.draw(area, buf, ctx);
            return;
        };
        let code_w = code[0].chars().count() as u16;
        let words = Rect::new(area.x, area.y, area.width - code_w - GAP, area.height);
        self.detail.draw(words, buf, ctx);
        let x = area.right() - code_w;
        let top = area.y + area.height.saturating_sub(code.len() as u16) / 2;
        for (i, row) in code.iter().enumerate() {
            put(buf, x, top + i as u16, row, code_w, qr::ink());
        }
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, String)> {
        vec![("⏎", t("continue"))]
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

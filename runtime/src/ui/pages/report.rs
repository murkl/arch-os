//! Report page of a run or action, on success with text or on failure. The module gives the
//! text, the runtime the mark and the QR code.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use crate::i18n::t;
use crate::ui::detail::{Block, Detail, mark, words};
use crate::ui::draw::put;
use crate::ui::{Ctx, Flow, Key, Page, Tone, qr};

/// Where the page leads once read.
pub enum Close {
    PopN(usize),
}

pub struct ReportPage {
    title: String,
    text: String,
    /// Value shown as QR code and as text under the report.
    qr: Option<String>,
    /// One line under the text, such as a run's tally of optional tasks and tests.
    note: Option<(String, Tone)>,
    stopped: bool,
    close: Close,
    detail: Detail,
}

/// Minimum text width. Below it the QR code is dropped.
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
    /// Closes at once. Unattended, the log is the reader.
    fn unattended(&mut self, _: &mut Ctx) -> Result<Flow, String> {
        Ok(match &self.close {
            Close::PopN(n) => Flow::PopN(*n),
        })
    }

    fn title(&self) -> String {
        self.title.clone()
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        self.detail.set(self.blocks(), Vec::new());
        // Text and code side by side, text the larger part: a code under a paragraph needs more
        // rows than a frame has.
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

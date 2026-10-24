//! Language page under the wordmark, before anything else. The only untranslated page.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use super::Then;
use crate::i18n::{self, t};
use crate::ui::draw::{center, width};
use crate::ui::list::{List, Picked, Row};
use crate::ui::{Ctx, Flow, Key, Nav, Page, Tone};

/// Short, plain English, since no catalog translates it.
pub const CHOOSE: &str = "Language";
const KEYS: &str = "↑↓ move · ⏎ confirm · q quit";

fn rows() -> Vec<Row<String>> {
    i18n::langs()
        .into_iter()
        .map(|l| Row::new(l.code, l.name))
        .collect()
}

/// Sets the UI language and saves it with the answers.
fn speak(code: &str, ctx: &mut Ctx) {
    i18n::set(code);
    ctx.store.language = code.to_string();
    crate::info!("language {code}");
    ctx.save();
}

pub struct LanguagePage {
    list: List<String>,
}

impl LanguagePage {
    /// Opens on the machine's language where a catalog exists.
    pub fn new() -> LanguagePage {
        let mut list = List::new(rows());
        list.focus(&i18n::detect().to_string());
        LanguagePage { list }
    }
}

impl Page for LanguagePage {
    /// Only shown when the answer file has no language.
    fn unattended(&mut self, _: &mut Ctx) -> Result<Flow, String> {
        Err(crate::i18n::t("The answer file names no language."))
    }

    fn title(&self) -> String {
        String::new()
    }

    fn bare(&self) -> bool {
        true
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        bare(buf, area, ctx, Some(CHOOSE), &mut self.list, KEYS);
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, String)> {
        Vec::new()
    }

    fn key(&mut self, key: Key, ctx: &mut Ctx) -> Flow {
        match self.list.key(key) {
            Picked::Open(code) => {
                speak(&code, ctx);
                super::next(ctx)
            }
            Picked::Used => Flow::Stay,
            // The first page has nothing to go back to.
            Picked::Ignored if matches!(key.nav(false), Some(Nav::Back)) => Flow::Stay,
            Picked::Ignored => Flow::Ignored,
        }
    }
}

/// Page without frame: wordmark, a line, the rows and the keys as one block at the golden
/// section.
pub fn bare<I: Clone + PartialEq>(
    buf: &mut Buffer,
    area: Rect,
    ctx: &mut Ctx,
    caption: Option<&str>,
    list: &mut List<I>,
    keys: &str,
) {
    let s = ctx.style;
    let logo_rows = crate::spec::loaded().product.logo.len() as u16;
    let rows = list.rows().len() as u16;
    let block = logo_rows + 2 + if caption.is_some() { 2 } else { 0 } + rows + 2;
    let free = area.height.saturating_sub(block);
    let top = area.y + (free as f64 / 2.618).round() as u16;
    let mut y = super::splash::wordmark(buf, area, top, 1.0, ctx);
    if y > top {
        y += 2;
    }
    if let Some(caption) = caption {
        center(buf, area, y, caption, s.tone(Tone::Normal), "");
        y += 2;
    }
    let wide = list
        .rows()
        .iter()
        .map(|r| width(&r.label))
        .max()
        .unwrap_or(0) as u16
        + 2;
    let x = area.x + area.width.saturating_sub(wide) / 2;
    list.draw(
        Rect::new(x, y, wide, rows.min(area.bottom().saturating_sub(y))),
        buf,
        ctx,
    );
    y += rows + 1;
    let keys = keys
        .replace("↑↓", s.glyphs.up_down)
        .replace('⏎', s.glyphs.enter)
        .replace('·', s.glyphs.separator);
    if y < area.bottom() {
        center(buf, area, y, &keys, s.tone(Tone::Muted), "");
    }
}

/// The same choice from the dashboard, inside the frame.
pub struct LangPage {
    list: List<String>,
    then: Then,
}

impl LangPage {
    pub fn new(then: Then) -> LangPage {
        let mut list = List::new(rows());
        list.focus(&i18n::current().code);
        LangPage { list, then }
    }
}

impl Page for LangPage {
    fn title(&self) -> String {
        t("Interface language")
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        let text = t("Changes only the interface language.");
        let y =
            crate::ui::draw::paragraph(buf, area, area.y, &text, ctx.style.tone(Tone::Muted)) + 1;
        self.list.draw(
            Rect::new(area.x, y, area.width, area.bottom().saturating_sub(y)),
            buf,
            ctx,
        );
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, String)> {
        vec![("↑↓", t("choose")), ("⏎", t("use")), ("esc", t("back"))]
    }

    fn key(&mut self, key: Key, ctx: &mut Ctx) -> Flow {
        match self.list.key(key) {
            Picked::Open(code) => {
                speak(&code, ctx);
                super::after(&self.then, ctx)
            }
            Picked::Used => Flow::Stay,
            Picked::Ignored => Flow::Ignored,
        }
    }
}

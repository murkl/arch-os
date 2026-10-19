//! A page of facts with its actions underneath. The facts scroll, the actions stay.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Style as Cell;

use super::draw::{cut, put, scrollbar, width, wrap};
use super::list::{Lead, List, Picked, Row, draw_row};
use super::{Ctx, Flow, Key, Nav, Style, Tone};
use crate::i18n::{t, tf};
use crate::script::Failure;

/// The mark a finished run is headed by, drawn out of blocks: a font's own tick is one cell
/// tall whatever it is set beside, and this one has a whole page under it.
pub const TICK: [&str; 5] = [
    "           ▄█▀",
    "         ▄█▀",
    "█▄     ▄█▀",
    " ▀█▄ ▄█▀",
    "   ▀██▀",
];

/// The mark over a run that could not go on, out of the same blocks at the same size.
pub const CROSS: [&str; 5] = [
    "▀█▄     ▄█▀",
    "  ▀█▄ ▄█▀",
    "    ███",
    "  ▄█▀ ▀█▄",
    "▄█▀     ▀█▄",
];

#[derive(Clone, Debug, PartialEq)]
pub enum Block {
    Field(String, String, Tone),
    Text(String, Tone),
    Heading(String),
    /// Lines kept as they are, each in its tone.
    Code(Vec<(String, Tone)>),
    /// A picture, line by line, in one tone.
    Picture(Vec<String>, Tone),
    /// Text beside the lead column, wrapped under itself.
    Note(Lead, String, Tone),
    Blank,
}

pub struct Act {
    pub label: String,
    pub lead: Lead,
    /// What the action is about, on the right.
    pub note: Option<(String, Tone)>,
    pub description: String,
    pub go: Box<dyn FnMut(&mut Ctx) -> Flow>,
}

impl Act {
    pub fn new(label: impl Into<String>, go: impl FnMut(&mut Ctx) -> Flow + 'static) -> Act {
        Act {
            label: label.into(),
            lead: Lead::None,
            note: None,
            description: String::new(),
            go: Box::new(go),
        }
    }

    pub fn describe(mut self, text: impl Into<String>) -> Act {
        self.description = text.into();
        self
    }
}

#[derive(Default)]
pub struct Detail {
    pub body: Vec<Block>,
    acts: Vec<Act>,
    list: List<usize>,
    scroll: usize,
    page: usize,
    /// The facts are longer than their room, as last drawn.
    overflow: bool,
}

impl Detail {
    pub fn set(&mut self, body: Vec<Block>, acts: Vec<Act>) {
        self.body = body;
        self.list.described = acts.iter().any(|a| !a.description.is_empty());
        let rows = acts
            .iter()
            .enumerate()
            .map(|(i, a)| {
                let mut row = Row::new(i, a.label.clone()).describe(a.description.clone());
                row.lead = a.lead;
                match &a.note {
                    Some((text, tone)) => row.detail(text.clone(), *tone),
                    None => row,
                }
            })
            .collect();
        self.list.set(rows);
        self.acts = acts;
    }

    /// Puts the cursor on an action, by its position.
    pub fn focus(&mut self, index: usize) {
        self.list.focus(&index);
    }

    pub fn key(&mut self, key: Key, ctx: &mut Ctx) -> Flow {
        let scroll_only = self.acts.is_empty();
        match key.nav(false) {
            Some(Nav::PageUp) => self.scroll = self.scroll.saturating_sub(self.page.max(1)),
            Some(Nav::PageDown) => self.scroll += self.page.max(1),
            Some(Nav::Up) if scroll_only || key == Key::WheelUp => {
                self.scroll = self.scroll.saturating_sub(1)
            }
            Some(Nav::Down) if scroll_only || key == Key::WheelDown => self.scroll += 1,
            Some(Nav::Top) if scroll_only => self.scroll = 0,
            Some(Nav::Bottom) if scroll_only => self.scroll = usize::MAX / 2,
            _ => {
                return match self.list.key(key) {
                    Picked::Open(i) => (self.acts[i].go)(ctx),
                    Picked::Used => Flow::Stay,
                    Picked::Ignored => Flow::Ignored,
                };
            }
        }
        Flow::Stay
    }

    /// The lines the facts take at this width.
    pub fn height(&self, width: u16, ctx: &Ctx) -> u16 {
        render(&self.body, width as usize, ctx).len() as u16
    }

    pub fn hints(&self) -> Vec<(&'static str, String)> {
        let mut h = Vec::new();
        if self.acts.is_empty() {
            if self.overflow {
                h.push(("↑↓", t("scroll")));
            }
            h.push(("⏎", t("continue")));
        } else {
            h.push(("↑↓", t("choose")));
            h.push(("⏎", t("open")));
            if self.overflow {
                h.push(("⇞⇟", t("scroll")));
            }
        }
        h
    }

    pub fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &Ctx) {
        let s = &ctx.style;
        let acts_height = if self.acts.is_empty() {
            0
        } else {
            self.list.height() as u16 + 1
        };
        let body_height = area.height.saturating_sub(acts_height) as usize;
        let lines = render(&self.body, area.width as usize, ctx);
        self.page = body_height.saturating_sub(1);
        self.scroll = self.scroll.min(lines.len().saturating_sub(body_height));
        self.overflow = lines.len() > body_height;
        let column = lines
            .iter()
            .any(|l| matches!(l, Line::Row(lead, ..) if *lead != Lead::None));
        for (n, line) in lines.iter().skip(self.scroll).take(body_height).enumerate() {
            let y = area.y + n as u16;
            match line {
                Line::Spans(spans) => {
                    let mut x = area.x;
                    for (text, tone, bold) in spans {
                        let style = if *bold { s.bold(*tone) } else { s.tone(*tone) };
                        x = put(buf, x, y, text, area.right().saturating_sub(x), style);
                    }
                }
                Line::Row(lead, label) => {
                    fn styled<'a>(pieces: &'a [(String, Tone)], s: &Style) -> Vec<(&'a str, Cell)> {
                        pieces
                            .iter()
                            .map(|(text, tone)| (text.as_str(), s.tone(*tone)))
                            .collect()
                    }
                    draw_row(buf, area, y, (*lead, column), &styled(label, s), &[], ctx)
                }
            }
        }
        let rest = Rect::new(area.x, area.y, area.width, body_height as u16);
        scrollbar(buf, rest, lines.len(), self.scroll, ctx);
        if !self.acts.is_empty() {
            let rows = acts_height.saturating_sub(1).min(area.height);
            self.list.draw(
                Rect::new(area.x, area.y + area.height - rows, area.width, rows),
                buf,
                ctx,
            );
        }
    }
}

pub type Span = (String, Tone, bool);

enum Line {
    Spans(Vec<Span>),
    Row(Lead, Vec<(String, Tone)>),
}

/// The column the fields' labels take: the widest, up to a third of the width.
fn label_width(body: &[Block], w: usize) -> usize {
    body.iter()
        .filter_map(|b| match b {
            Block::Field(l, ..) => Some(width(l)),
            _ => None,
        })
        .max()
        .unwrap_or(0)
        .min(w / 3)
}

/// The blocks as screen lines of the given width.
fn render(body: &[Block], w: usize, ctx: &Ctx) -> Vec<Line> {
    let mark = ctx.style.glyphs.ellipsis;
    let label_width = label_width(body, w);
    let mut out: Vec<Line> = Vec::new();
    for block in body {
        match block {
            Block::Field(label, value, tone) => {
                let room = w.saturating_sub(label_width + 2).max(1);
                for (i, line) in wrap(value, room).into_iter().enumerate() {
                    let head = if i == 0 {
                        cut(label, label_width, mark)
                    } else {
                        String::new()
                    };
                    let pad = " ".repeat(label_width - width(&head) + 2);
                    out.push(Line::Spans(vec![
                        (head + &pad, Tone::Muted, false),
                        (line, *tone, false),
                    ]));
                }
            }
            Block::Text(text, tone) => out.extend(
                wrap(text, w)
                    .into_iter()
                    .map(|l| Line::Spans(vec![(l, *tone, false)])),
            ),
            Block::Heading(text) => out.extend(
                wrap(text, w)
                    .into_iter()
                    .map(|l| Line::Spans(vec![(l, Tone::Normal, true)])),
            ),
            Block::Code(lines) => out.extend(
                lines
                    .iter()
                    .map(|(l, tone)| Line::Spans(vec![(cut(l, w, mark), *tone, false)])),
            ),
            Block::Picture(lines, tone) => out.extend(
                lines
                    .iter()
                    .map(|l| Line::Spans(vec![(cut(l, w, ""), *tone, true)])),
            ),
            Block::Note(lead, text, tone) => {
                for (i, line) in wrap(text, w.saturating_sub(2)).into_iter().enumerate() {
                    let lead = if i == 0 { *lead } else { Lead::None };
                    out.push(Line::Row(lead, vec![(line, *tone)]));
                }
            }
            Block::Blank => out.push(Line::Spans(Vec::new())),
        }
    }
    out
}

/// How a failure reads on any page: where exactly, in fixed rows, then what the tool said on its
/// way out, then where the rest is.
pub fn failure(f: &Failure) -> Vec<Block> {
    let mut b: Vec<Block> = f
        .fields()
        .into_iter()
        .map(|(label, value)| Block::Field(label, value, Tone::Normal))
        .collect();
    if !f.stderr.is_empty() {
        b.push(Block::Blank);
        let lines: Vec<&str> = f.stderr.lines().collect();
        b.push(Block::Code(
            lines[lines.len().saturating_sub(8)..]
                .iter()
                .map(|l| (l.to_string(), Tone::Error))
                .collect(),
        ));
    }
    if let Some(path) = crate::log::path() {
        b.push(Block::Blank);
        b.push(Block::Text(
            tf("Full log: {{path}}", &[("path", &path.display())]),
            Tone::Muted,
        ));
    }
    b
}

/// What a page says in the words of a declaration: the headline, then the rest.
pub fn words(text: &str) -> Vec<Block> {
    let (head, body) = crate::spec::text::split(text);
    let mut b = vec![Block::Heading(head.to_string())];
    if !body.is_empty() {
        b.push(Block::Blank);
        b.push(Block::Text(body.to_string(), Tone::Normal));
    }
    b
}

/// A finished run's mark, or a stopped one's.
pub fn mark(stopped: bool) -> Block {
    let picture = if stopped { CROSS } else { TICK };
    Block::Picture(
        picture.iter().map(|l| l.to_string()).collect(),
        if stopped { Tone::Error } else { Tone::Ok },
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn drawn(d: &mut Detail, area: Rect, ctx: &Ctx) -> Vec<String> {
        let mut buf = Buffer::empty(Rect::new(0, 0, area.right() + 2, area.bottom()));
        d.draw(area, &mut buf, ctx);
        (0..buf.area.height)
            .map(|y| (0..buf.area.width).map(|x| buf[(x, y)].symbol()).collect())
            .collect()
    }

    #[test]
    fn facts_longer_than_their_room_scroll_while_the_actions_stay() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let (mut app, _, _) = crate::ui::app::tests::app(true);
        let mut d = Detail::default();
        let body = (0..50)
            .map(|i| Block::Text(format!("line {i}"), Tone::Normal))
            .collect();
        d.set(
            body,
            vec![
                Act::new("Go", |_| Flow::Stay),
                Act::new("Other", |_| Flow::Stay),
            ],
        );
        let area = Rect::new(2, 0, 30, 10);
        let rows = drawn(&mut d, area, &app.ctx);
        assert!(
            rows[0].contains("line 0") && rows[6].contains("line 6"),
            "{rows:#?}"
        );
        assert!(d.hints().iter().any(|(k, _)| *k == "⇞⇟"));
        d.key(Key::WheelDown, &mut app.ctx);
        let rows = drawn(&mut d, area, &app.ctx);
        assert!(rows[0].contains("line 1"), "{rows:#?}");
        assert!(
            rows[8].starts_with("▶") && rows[8].contains("Go"),
            "the action stays chosen: {rows:#?}"
        );
        d.key(Key::PageDown, &mut app.ctx);
        assert!(drawn(&mut d, area, &app.ctx)[0].contains("line 7"));
    }

    #[test]
    fn a_failure_reads_where_then_what_the_tool_said() {
        let _lang = crate::i18n::LOCK.lock().unwrap_or_else(|e| e.into_inner());
        crate::i18n::set("en");
        let f = Failure {
            module: "Installer".into(),
            unit: "Partition the disk".into(),
            script: "installer/tasks/partition/task.sh".into(),
            line: 12,
            code: 3,
            command: "sgdisk -o /dev/sda".into(),
            stderr: "sgdisk: no such device".into(),
            ..Failure::default()
        };
        let blocks = failure(&f);
        assert_eq!(
            blocks[0],
            Block::Field("Module".into(), "Installer".into(), Tone::Normal)
        );
        assert_eq!(
            blocks[2],
            Block::Field(
                "Script".into(),
                "installer/tasks/partition/task.sh:12".into(),
                Tone::Normal
            )
        );
        assert!(matches!(&blocks[6], Block::Code(lines) if lines[0].0 == "sgdisk: no such device"));
    }
}

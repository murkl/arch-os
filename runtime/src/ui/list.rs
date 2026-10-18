//! The list every page selects from: headings, a cursor in the margin, a column for a mark, a
//! value on the right and a filter.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Style as Cell;

use super::draw::{cut, put, width};
use super::input::Input;
use super::{Ctx, Key, Nav, Tone};
use crate::i18n::t;

/// What stands in the column before a label: every row has it, so labels line up on every page.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub enum Lead {
    #[default]
    None,
    /// A mark in its tone: a step's state, a chosen row.
    Glyph(&'static str, Tone),
}

#[derive(Clone, Debug, PartialEq)]
pub struct Row<I> {
    /// What choosing the row means to its page. A heading means nothing.
    pub id: Option<I>,
    pub label: String,
    /// Right-aligned: a value, a count, a state.
    pub detail: String,
    pub tone: Tone,
    pub lead: Lead,
    /// Shown, but its action is not available here.
    pub dim: bool,
    pub heading: bool,
    /// What the row is about, for the line under the list where a page shows one.
    pub description: String,
}

impl<I> Row<I> {
    pub fn new(id: I, label: impl Into<String>) -> Row<I> {
        Row {
            id: Some(id),
            ..Row::blank(label)
        }
    }

    pub fn heading(label: impl Into<String>) -> Row<I> {
        Row {
            heading: true,
            ..Row::blank(label)
        }
    }

    fn blank(label: impl Into<String>) -> Row<I> {
        Row {
            id: None,
            label: label.into(),
            detail: String::new(),
            tone: Tone::Muted,
            lead: Lead::None,
            dim: false,
            heading: false,
            description: String::new(),
        }
    }

    pub fn detail(mut self, detail: impl Into<String>, tone: Tone) -> Row<I> {
        self.detail = detail.into();
        self.tone = tone;
        self
    }

    pub fn describe(mut self, text: impl Into<String>) -> Row<I> {
        self.description = text.into();
        self
    }
}

/// The columns of a row: the lead where the page has a column for it, the label and the detail,
/// each in pieces of their own style. The detail gets what the label leaves, at least half.
pub fn draw_row(
    buf: &mut Buffer,
    area: Rect,
    y: u16,
    (lead, column): (Lead, bool),
    label: &[(&str, Cell)],
    detail: &[(&str, Cell)],
    ctx: &Ctx,
) {
    let s = &ctx.style;
    if let Lead::Glyph(glyph, tone) = lead {
        put(buf, area.x, y, glyph, 1, s.tone(tone));
    }
    let x = area.x + if column { 2 } else { 0 };
    let room = area.right().saturating_sub(x) as usize;
    let fit = |pieces: &[(&str, Cell)], mut left: usize| {
        let mut out = Vec::new();
        for (text, style) in pieces {
            let piece = cut(text, left, s.glyphs.ellipsis);
            left -= width(&piece);
            let whole = piece == *text;
            out.push((piece, *style));
            if !whole {
                break;
            }
        }
        (out, left)
    };
    let label_width: usize = label.iter().map(|(t, _)| width(t)).sum();
    let budget = (room / 2).max(room.saturating_sub(label_width + 2));
    let (pieces, left) = fit(detail, budget);
    let detail_width = budget - left;
    let label_room = room.saturating_sub(if detail_width == 0 {
        0
    } else {
        detail_width + 2
    });
    let (name, _) = fit(label, label_room);
    let mut lx = x;
    for (piece, style) in &name {
        lx = put(
            buf,
            lx,
            y,
            piece,
            (x + label_room as u16).saturating_sub(lx),
            *style,
        );
    }
    let mut x = area.right() - detail_width as u16;
    for (piece, style) in &pieces {
        x = put(buf, x, y, piece, width(piece) as u16, *style);
    }
}

pub enum Picked<I> {
    /// The list used the key.
    Used,
    Open(I),
    Ignored,
}

pub struct List<I> {
    rows: Vec<Row<I>>,
    cursor: usize,
    offset: usize,
    pub filter: Option<Input>,
    /// The row under the cursor shows its description under the list.
    pub described: bool,
    height: usize,
}

impl<I> Default for List<I> {
    fn default() -> Self {
        List {
            rows: Vec::new(),
            cursor: 0,
            offset: 0,
            filter: None,
            described: false,
            height: 0,
        }
    }
}

impl<I: Clone + PartialEq> List<I> {
    pub fn new(rows: Vec<Row<I>>) -> List<I> {
        let mut l = List::default();
        l.set(rows);
        l
    }

    /// Replaces the rows. The cursor stays on its row, or where its row was when it is gone.
    pub fn set(&mut self, rows: Vec<Row<I>>) {
        let id = self.selected().and_then(|r| r.id.clone());
        let at = self
            .shown()
            .iter()
            .position(|&i| i == self.cursor)
            .unwrap_or(0);
        self.rows = rows;
        if id.as_ref().is_some_and(|id| self.focus(id)) {
            return;
        }
        let shown = self.shown();
        self.cursor = shown
            .get(at.min(shown.len().saturating_sub(1)))
            .copied()
            .unwrap_or(0);
    }

    pub fn focus(&mut self, id: &I) -> bool {
        match self
            .shown()
            .into_iter()
            .find(|&i| self.rows[i].id.as_ref() == Some(id))
        {
            Some(i) => {
                self.cursor = i;
                true
            }
            None => false,
        }
    }

    pub fn rows(&self) -> &[Row<I>] {
        &self.rows
    }

    /// Indices of the selectable rows the filter lets through, by label, detail and heading.
    fn shown(&self) -> Vec<usize> {
        let query = self
            .filter
            .as_ref()
            .map(|f| f.text.to_lowercase())
            .unwrap_or_default();
        let mut heading = String::new();
        let mut out = Vec::new();
        for (i, r) in self.rows.iter().enumerate() {
            if r.heading {
                heading = r.label.to_lowercase();
                continue;
            }
            if query.is_empty()
                || r.label.to_lowercase().contains(&query)
                || r.detail.to_lowercase().contains(&query)
                || heading.contains(&query)
            {
                out.push(i);
            }
        }
        out
    }

    pub fn selected(&self) -> Option<&Row<I>> {
        self.shown()
            .contains(&self.cursor)
            .then(|| &self.rows[self.cursor])
    }

    pub fn typing(&self) -> bool {
        self.filter.is_some()
    }

    pub fn open_filter(&mut self) {
        if self.filter.is_none() {
            self.filter = Some(Input::new(&t("Filter")));
        }
    }

    fn step(&mut self, by: isize) {
        let shown = self.shown();
        if shown.is_empty() {
            return;
        }
        let at = shown.iter().position(|&i| i == self.cursor).unwrap_or(0) as isize;
        let next = (at + by).clamp(0, shown.len() as isize - 1);
        self.cursor = shown[next as usize];
    }

    pub fn key(&mut self, key: Key) -> Picked<I> {
        let typing = self.filter.is_some();
        match key.nav(typing) {
            Some(Nav::Up) => self.step(-1),
            Some(Nav::Down) => self.step(1),
            Some(Nav::PageUp) => self.step(-(self.height.max(2) as isize - 1)),
            Some(Nav::PageDown) => self.step(self.height.max(2) as isize - 1),
            Some(Nav::Top) => self.step(isize::MIN / 2),
            Some(Nav::Bottom) => self.step(isize::MAX / 2),
            Some(Nav::Open) => {
                return self
                    .selected()
                    .and_then(|r| r.id.clone())
                    .map_or(Picked::Used, Picked::Open);
            }
            Some(Nav::Filter) => self.open_filter(),
            Some(Nav::Back) if typing => self.filter = None,
            _ => {
                let Some(filter) = self.filter.as_mut() else {
                    return Picked::Ignored;
                };
                if key == Key::Backspace && filter.text.is_empty() {
                    self.filter = None;
                } else if !filter.key(key) {
                    return Picked::Ignored;
                }
                let shown = self.shown();
                if !shown.contains(&self.cursor) {
                    self.cursor = shown.first().copied().unwrap_or(self.cursor);
                }
            }
        }
        Picked::Used
    }

    /// The rows this list would take with nothing in its way: for a page that puts something
    /// right under it.
    pub fn height(&self) -> usize {
        let shown = self.shown();
        let headings = self
            .rows
            .iter()
            .enumerate()
            .filter(|(i, r)| r.heading && (!r.label.is_empty() || *i > 0))
            .count();
        shown.len() + headings + if self.described { 3 } else { 0 }
    }

    pub fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &Ctx) {
        let s = &ctx.style;
        let mut y = area.y;
        if let Some(filter) = &self.filter {
            filter.draw(buf, area.x, y, area.width, ctx);
            y += 2;
        }
        let described = self.described && area.bottom().saturating_sub(y) > 4;
        let height = area
            .bottom()
            .saturating_sub(y)
            .saturating_sub(if described { 3 } else { 0 }) as usize;
        self.height = height;
        let shown = self.shown();
        let query_active = self.filter.as_ref().is_some_and(|f| !f.text.is_empty());
        // Headings stay while a filter is empty. A filtered list is flat.
        let visible: Vec<usize> = (0..self.rows.len())
            .filter(|&i| shown.contains(&i) || (self.rows[i].heading && !query_active))
            .collect();
        if shown.is_empty() {
            if query_active {
                put(
                    buf,
                    area.x,
                    y,
                    &t("No matches"),
                    area.width,
                    s.tone(Tone::Muted),
                );
            }
            return;
        }
        // Each heading after the first gets a blank line before it. An empty one is only that.
        let mut lines: Vec<Option<usize>> = Vec::new();
        for &i in &visible {
            if self.rows[i].heading && !lines.is_empty() {
                lines.push(None);
            }
            if !(self.rows[i].heading && self.rows[i].label.is_empty()) {
                lines.push(Some(i));
            }
        }
        let at = lines
            .iter()
            .position(|l| *l == Some(self.cursor))
            .unwrap_or(0);
        if at < self.offset {
            self.offset = at.saturating_sub(usize::from(
                at > 0 && lines[at - 1].is_some_and(|i| self.rows[i].heading),
            ));
        } else if at >= self.offset + height {
            self.offset = at + 1 - height;
        }
        self.offset = self.offset.min(lines.len().saturating_sub(height.max(1)));
        let rows = Rect::new(area.x, y, area.width, height as u16);
        super::draw::scrollbar(buf, rows, lines.len(), self.offset, ctx);
        let column = self.rows.iter().any(|r| r.lead != Lead::None);
        for (n, line) in lines.iter().skip(self.offset).take(height).enumerate() {
            let Some(i) = *line else { continue };
            let row = &self.rows[i];
            let ly = y + n as u16;
            if row.heading {
                put(
                    buf,
                    area.x,
                    ly,
                    &cut(&row.label, area.width as usize, s.glyphs.ellipsis),
                    area.width,
                    s.bold(Tone::Muted),
                );
                continue;
            }
            let current = i == self.cursor;
            if current && area.x >= 2 {
                put(
                    buf,
                    area.x - 2,
                    ly,
                    s.glyphs.cursor,
                    1,
                    s.tone(Tone::Accent),
                );
            }
            let lead = match row.lead {
                Lead::Glyph(glyph, _) if row.dim => Lead::Glyph(glyph, Tone::Muted),
                other => other,
            };
            let style = match (current, row.dim) {
                (true, _) => s.bold(Tone::Accent),
                (false, true) => s.tone(Tone::Muted),
                (false, false) => s.tone(Tone::Normal),
            };
            // Muted reads badly beside the cursor: the row under it is the one being read.
            let detail_tone = match (current, row.tone) {
                (true, Tone::Muted) => Tone::Normal,
                (_, tone) => tone,
            };
            draw_row(
                buf,
                area,
                ly,
                (lead, column),
                &[(&row.label, style)],
                &[(&row.detail, s.tone(detail_tone))],
                ctx,
            );
            if current {
                // The whole row on the surface, from the cursor in the margin to the right edge,
                // so the eye finds its value.
                let from = area.x.saturating_sub(2);
                buf.set_style(
                    Rect::new(from, ly, area.right() - from, 1),
                    Cell::new().bg(s.selection),
                );
            }
        }
        if described {
            let text = self
                .selected()
                .map(|r| r.description.clone())
                .unwrap_or_default();
            let under = Rect::new(area.x, y + height as u16 + 1, area.width, 2);
            super::draw::paragraph(buf, under, under.y, &text, s.tone(Tone::Muted));
        }
    }
}

/// The footer of a plain list.
pub fn hints(filter: bool) -> Vec<(&'static str, String)> {
    if filter {
        return vec![
            ("↑↓", t("choose")),
            ("⏎", t("open")),
            ("esc", t("close filter")),
        ];
    }
    vec![
        ("↑↓", t("choose")),
        ("⏎", t("open")),
        ("f", t("filter")),
        ("esc", t("back")),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    fn list() -> List<&'static str> {
        List::new(vec![
            Row::heading("Region"),
            Row::new("1", "Keyboard"),
            Row::new("2", "Time zone"),
            Row::heading("Storage"),
            Row::new("3", "Disk"),
        ])
    }

    #[test]
    fn skips_headings_stops_at_the_ends_and_filters_by_heading_too() {
        let mut l = list();
        assert_eq!(l.selected().unwrap().id, Some("1"));
        l.key(Key::Down);
        l.key(Key::Char('j'));
        assert_eq!(l.selected().unwrap().id, Some("3"));
        l.key(Key::Down);
        assert_eq!(l.selected().unwrap().id, Some("3"));
        l.key(Key::Char('g'));
        assert_eq!(l.selected().unwrap().id, Some("1"));
        l.key(Key::Char('f'));
        assert!(l.typing());
        for c in "stor".chars() {
            assert!(matches!(l.key(Key::Char(c)), Picked::Used));
        }
        assert_eq!(l.selected().unwrap().id, Some("3"), "found by its heading");
        assert!(matches!(l.key(Key::Enter), Picked::Open(id) if id == "3"));
        l.key(Key::Esc);
        assert!(!l.typing());
        assert!(
            matches!(l.key(Key::Esc), Picked::Ignored),
            "without a filter esc is the page's"
        );
    }

    #[test]
    fn keeps_the_cursor_on_its_row_when_rows_change() {
        let mut l = list();
        l.key(Key::Down);
        l.set(vec![Row::new("0", "New"), Row::new("2", "Time zone")]);
        assert_eq!(l.selected().unwrap().id, Some("2"));
        l.set(vec![Row::new("0", "New"), Row::new("9", "Other")]);
        assert_eq!(l.selected().unwrap().id, Some("9"), "where its row was");
    }
}

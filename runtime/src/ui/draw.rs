//! Page frame and shared drawing primitives.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Style as Cell;
use unicode_width::{UnicodeWidthChar, UnicodeWidthStr};

use super::{Ctx, Does, Tone};
use crate::i18n::t;

pub fn width(s: &str) -> usize {
    s.width()
}

pub fn cut(s: &str, max: usize, mark: &str) -> String {
    if s.width() <= max {
        return s.to_string();
    }
    let room = max.saturating_sub(mark.width());
    let mut out = String::new();
    let mut used = 0;
    for c in s.chars() {
        let w = c.width().unwrap_or(0);
        if used + w > room {
            break;
        }
        used += w;
        out.push(c);
    }
    // A sequence, such as an emoji with its variation selector, is wider than its characters.
    while out.width() > room {
        out.pop();
    }
    out + if max >= mark.width() { mark } else { "" }
}

/// Cuts at the front, where a path says least.
pub fn cut_front(s: &str, max: usize, mark: &str) -> String {
    if s.width() <= max {
        return s.to_string();
    }
    let room = max.saturating_sub(mark.width());
    let mut kept: Vec<char> = Vec::new();
    let mut used = 0;
    for c in s.chars().rev() {
        let w = c.width().unwrap_or(0);
        if used + w > room {
            break;
        }
        used += w;
        kept.push(c);
    }
    let mut kept: String = kept.into_iter().rev().collect();
    while kept.width() > room {
        kept.remove(0);
    }
    mark.to_string() + &kept
}

/// Whole `pieces` that fit in `max` columns, joined by `sep`, the rest as `mark`.
pub fn fit(pieces: &[String], sep: &str, max: usize, mark: &str) -> String {
    let all = pieces.join(sep);
    if all.width() <= max {
        return all;
    }
    let mut kept = String::new();
    for piece in pieces {
        let next = match kept.is_empty() {
            true => piece.clone(),
            false => format!("{kept}{sep}{piece}"),
        };
        if next.width() + sep.width() + mark.width() > max {
            break;
        }
        kept = next;
    }
    match kept.is_empty() {
        true => cut(&all, max, mark),
        false => format!("{kept}{sep}{mark}"),
    }
}

/// Writes up to `max` columns and returns the end column.
pub fn put(buf: &mut Buffer, x: u16, y: u16, s: &str, max: u16, style: Cell) -> u16 {
    if max == 0 || y >= buf.area.bottom() || x >= buf.area.right() {
        return x;
    }
    buf.set_stringn(x, y, s, max as usize, style).0
}

/// Word wrap that keeps blank lines. A word wider than the line breaks after its last fitting
/// `/`, else `-`, as paths and links read.
pub fn wrap(s: &str, width: usize) -> Vec<String> {
    let width = width.max(1);
    let mut lines = Vec::new();
    for para in s.split('\n') {
        let mut line = String::new();
        for word in para.split_whitespace() {
            let mut word = word.to_string();
            while word.width() > width {
                let mut head: String = cut(&word, width, "");
                let at = head.rfind('/').or_else(|| head.rfind('-'));
                if let Some(at) = at.filter(|&at| at > 0) {
                    head.truncate(at + 1);
                }
                if head.is_empty() {
                    head = word.chars().next().map(String::from).unwrap_or_default();
                }
                word = word[head.len()..].to_string();
                if !line.is_empty() {
                    lines.push(std::mem::take(&mut line));
                }
                lines.push(head);
            }
            if line.is_empty() {
                line = word;
            } else if line.width() + 1 + word.width() <= width {
                line.push(' ');
                line.push_str(&word);
            } else {
                lines.push(std::mem::replace(&mut line, word));
            }
        }
        lines.push(line);
    }
    lines
}

fn padding(width: u16) -> u16 {
    match width {
        0..40 => 1,
        40..70 => 2,
        _ => 4,
    }
}

const MAX_WIDTH: u16 = 100;

/// Content column: left edge, width, header row, footer row.
pub(super) fn geometry(area: Rect) -> Option<(u16, u16, u16, u16)> {
    let pad = padding(area.width);
    let width = area.width.saturating_sub(2 * pad).min(MAX_WIDTH);
    let x = area.x + (area.width - width) / 2;
    if area.height < 6 || width < 10 {
        return None;
    }
    let margin = u16::from(area.height > 16);
    Some((x, width, area.y + margin, area.bottom() - 1 - margin))
}

/// Draws the header and returns the page area. Header path on the left, activity and status or
/// the page's note on the right.
pub fn frame(
    area: Rect,
    buf: &mut Buffer,
    ctx: &Ctx,
    path: &[String],
    note: Option<String>,
) -> Rect {
    let s = &ctx.style;
    buf.set_style(area, s.base());
    let Some((x, width, top, bottom)) = geometry(area) else {
        return area;
    };
    let busy = if ctx.busy() { s.spinner() } else { "" };
    let (mark, mut right, tone) = match (note, ctx.status, ctx.module_status()) {
        (Some(note), _, _) => ("", note, Tone::Muted),
        (None, Some(true), Some(st)) => (s.glyphs.dot, t(&st.pass), Tone::Ok),
        (None, Some(false), Some(st)) => (s.glyphs.ring, t(&st.fail), Tone::Muted),
        _ => ("", String::new(), Tone::Muted),
    };
    let sep = format!(" {} ", s.glyphs.path);
    let mut parts = vec![(ctx.product_title(), s.bold(Tone::Accent))];
    for (i, p) in path.iter().enumerate() {
        parts.push((sep.clone(), s.tone(Tone::Muted)));
        let last = i + 1 == path.len();
        parts.push((
            p.clone(),
            if last {
                s.bold(Tone::Normal)
            } else {
                s.tone(Tone::Normal)
            },
        ));
    }
    let full: usize = parts.iter().map(|(t, _)| t.width()).sum();
    let right_width = |right: &str| {
        [busy, mark, right]
            .iter()
            .filter(|t| !t.is_empty())
            .map(|t| t.width() + 1)
            .sum::<usize>()
            + 2
    };
    // Short of room the status goes first, since it says less than the path.
    if full + right_width(&right) > width as usize {
        right.clear();
    }
    let room = (width as usize).saturating_sub(right_width(&right));
    let fixed: usize = parts[..parts.len() - 1]
        .iter()
        .map(|(t, _)| t.width())
        .sum();
    if full > room && fixed + 4 <= room {
        let last = parts.len() - 1;
        parts[last].0 = cut(&parts[last].0, room - fixed, s.glyphs.ellipsis);
    } else if full > room {
        // Narrower still, whole segments go from the front, where the path says least.
        let mark = (format!("{}{sep}", s.glyphs.ellipsis), s.tone(Tone::Muted));
        let width_of = |p: &[(String, Cell)]| p.iter().map(|(t, _)| t.width()).sum::<usize>();
        let last = parts.len() - 1;
        let from = (2..last)
            .step_by(2)
            .find(|&i| mark.0.width() + width_of(&parts[i..]) <= room)
            .unwrap_or(last);
        let mut kept = vec![mark];
        kept.extend(parts.split_off(from));
        let fixed = width_of(&kept[..kept.len() - 1]);
        let end = kept.len() - 1;
        kept[end].0 = cut(&kept[end].0, room.saturating_sub(fixed), s.glyphs.ellipsis);
        parts = kept;
    }
    let mut cx = x;
    for (text, style) in &parts {
        cx = put(buf, cx, top, text, (x + width).saturating_sub(cx), *style);
    }
    let mut rx = x + width;
    for (text, style) in [
        (right.as_str(), s.tone(tone)),
        (mark, s.tone(tone)),
        (busy, s.tone(Tone::Accent)),
    ] {
        if text.is_empty() {
            continue;
        }
        rx -= text.width() as u16;
        put(buf, rx, top, text, text.width() as u16, style);
        rx = rx.saturating_sub(1);
    }
    put(
        buf,
        x,
        top + 1,
        &s.glyphs.rule.repeat(width as usize),
        width,
        s.tone(Tone::Muted),
    );

    let content_top = top + 3;
    let content_bottom = bottom.saturating_sub(1);
    Rect::new(
        x,
        content_top,
        width,
        content_bottom.saturating_sub(content_top),
    )
}

/// Each key with its deed. Pages name keys as glyphs, the console shows them as words.
pub fn keys(ctx: &Ctx, hints: &[(&'static str, Does)]) -> Vec<String> {
    let g = &ctx.style.glyphs;
    hints
        .iter()
        .map(|(k, does)| {
            let key = match *k {
                "↑↓" => g.up_down,
                "⏎" => g.enter,
                "⇞⇟" => g.page_keys,
                other => other,
            };
            format!("{key} {}", does.label())
        })
        .collect()
}

/// Dimmed page keys with the version on the right. Drawn after the page, which knows its keys
/// only once drawn.
pub fn footer(area: Rect, buf: &mut Buffer, ctx: &Ctx, hints: &[(&'static str, Does)]) {
    let s = &ctx.style;
    let Some((x, width, _, bottom)) = geometry(area) else {
        return;
    };
    let version = crate::version::version();
    let keys = keys(ctx, hints);
    let sep = format!(" {} ", s.glyphs.separator);
    let line = keys.join(&sep);
    let room = (width as usize).saturating_sub(version.width() + 3);
    // Short of room the version goes first, then whole keys from the end.
    let shown = fit(&keys, &sep, width as usize, s.glyphs.ellipsis);
    put(buf, x, bottom, &shown, width, s.tone(Tone::Muted));
    if line.width() <= room {
        put(
            buf,
            x + width - version.width() as u16,
            bottom,
            version,
            version.width() as u16,
            s.tone(Tone::Muted),
        );
    }
}

/// Track in the right margin with a thumb sized and placed like the visible part. Nothing when
/// everything fits.
pub fn scrollbar(buf: &mut Buffer, area: Rect, lines: usize, offset: usize, ctx: &Ctx) {
    let s = &ctx.style;
    let shown = usize::from(area.height);
    let Some(x) = [area.right() + 1, area.right()]
        .into_iter()
        .find(|&x| x < buf.area.right())
    else {
        return;
    };
    if lines <= shown || shown == 0 {
        return;
    }
    let thumb = (shown * shown / lines).max(1);
    let hidden = lines - shown;
    let top = ((shown - thumb) * offset.min(hidden) + hidden / 2) / hidden;
    for i in 0..shown {
        let (glyph, style) = match i >= top && i < top + thumb {
            true => (s.glyphs.scroll[1], s.tone(Tone::Muted)),
            false => (
                s.glyphs.scroll[0],
                s.tone(Tone::Muted)
                    .add_modifier(ratatui::style::Modifier::DIM),
            ),
        };
        put(buf, x, area.y + i as u16, glyph, 1, style);
    }
}

pub fn center(buf: &mut Buffer, area: Rect, y: u16, text: &str, style: Cell, mark: &str) {
    let text = cut(text, area.width as usize, mark);
    let x = area.x + (area.width.saturating_sub(text.width() as u16)) / 2;
    put(buf, x, y, &text, area.width, style);
}

/// Returns the row after the wrapped text.
pub fn paragraph(buf: &mut Buffer, area: Rect, y: u16, text: &str, style: Cell) -> u16 {
    let mut y = y;
    for line in wrap(text, area.width as usize) {
        if y >= area.bottom() {
            break;
        }
        put(buf, area.x, y, &line, area.width, style);
        y += 1;
    }
    y
}

/// Centered spinner and title, with `under` below if given.
pub fn waiting(buf: &mut Buffer, area: Rect, title: &str, under: Option<&str>, ctx: &Ctx) {
    let s = &ctx.style;
    let top = area.y + area.height.saturating_sub(4) / 2;
    center(buf, area, top, s.spinner(), s.bold(Tone::Accent), "");
    center(
        buf,
        area,
        top + 2,
        title,
        s.bold(Tone::Normal),
        s.glyphs.ellipsis,
    );
    if let Some(under) = under {
        center(
            buf,
            area,
            top + 3,
            under,
            s.tone(Tone::Muted),
            s.glyphs.ellipsis,
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cuts_at_the_side_that_says_less() {
        assert_eq!(cut("Aktualisieren", 8, "…"), "Aktuali…");
        assert_eq!(
            cut_front("Arch OS › Installer › firefox", 12, "…"),
            "…r › firefox"
        );
        assert_eq!(cut("kurz", 8, "…"), "kurz");
        // A sequence, such as an emoji with its variation selector, is wider than its characters.
        for max in 1..12 {
            assert!(
                cut("⚠️ ⚠️ ⚠️ ⚠️ ⚠️", max, "…").width() <= max,
                "cut to {max}"
            );
            assert!(
                cut_front("⚠️ ⚠️ ⚠️ ⚠️ ⚠️", max, "…").width() <= max,
                "cut_front to {max}"
            );
        }
    }

    #[test]
    fn keeps_whole_pieces_and_marks_the_rest() {
        let keys = ["↑↓ choose", "⏎ open", "f filter", "q quit"].map(String::from);
        assert_eq!(
            fit(&keys, " · ", 40, "…"),
            "↑↓ choose · ⏎ open · f filter · q quit"
        );
        assert_eq!(fit(&keys, " · ", 30, "…"), "↑↓ choose · ⏎ open · …");
        assert_eq!(fit(&keys, " · ", 6, "…"), "↑↓ ch…");
    }

    #[test]
    fn wraps_on_words_and_breaks_long_ones() {
        assert_eq!(wrap("eins zwei drei", 9), ["eins zwei", "drei"]);
        assert_eq!(wrap("abcdefghij", 4), ["abcd", "efgh", "ij"]);
        assert_eq!(
            wrap("https://github.com/murkl/arch-os", 24),
            ["https://github.com/", "murkl/arch-os"]
        );
        assert_eq!(wrap("a\n\nb", 4), ["a", "", "b"]);
    }
}

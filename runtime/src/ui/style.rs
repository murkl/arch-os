//! Colors as styles, and the glyphs per terminal.
//!
//! Every color but the accent is a palette slot, so the UI reads under any terminal theme. The
//! accent is the product's, on the console its nearest stock color.

use ratatui::style::{Color, Modifier, Style as Cell};

use super::Tone;
use crate::spec::Rgb;

#[derive(Clone, Copy, Debug)]
pub struct Style {
    pub muted: Color,
    pub accent: Color,
    /// Background of the cursor row.
    pub selection: Color,
    /// Text on the selection, `Tone::Current`.
    on_selection: Color,
    pub success: Color,
    pub warning: Color,
    pub error: Color,
    pub glyphs: &'static Glyphs,
    /// Muted text is also dim. The console draws dark gray with a bright bit that only the normal
    /// intensity reset clears, which ending dim sends.
    dim_muted: bool,
}

#[derive(Debug)]
pub struct Glyphs {
    pub cursor: &'static str,
    /// State marks: filled, then hollow.
    pub dot: &'static str,
    pub ring: &'static str,
    pub rule: &'static str,
    pub path: &'static str,
    pub ellipsis: &'static str,
    pub separator: &'static str,
    pub bar: &'static str,
    pub track: &'static str,
    /// A scrollbar's track, then its thumb.
    pub scroll: [&'static str; 2],
    /// Step marks: ran, failed, skipped.
    pub ok: &'static str,
    pub fail: &'static str,
    pub skip: &'static str,
    /// Footer key names: up and down, enter, page up and down.
    pub up_down: &'static str,
    pub enter: &'static str,
    pub page_keys: &'static str,
    pub mask: &'static str,
    /// Density steps of a wordmark pixel coming into focus.
    pub focus: &'static [&'static str],
    pub spinner: &'static [&'static str],
}

impl Glyphs {
    /// Every glyph, to check against the console font.
    pub fn all(&self) -> Vec<&'static str> {
        let mut v = vec![
            self.cursor,
            self.dot,
            self.ring,
            self.rule,
            self.path,
            self.ellipsis,
            self.separator,
            self.bar,
            self.track,
            self.scroll[0],
            self.scroll[1],
            self.ok,
            self.fail,
            self.skip,
            self.up_down,
            self.enter,
            self.page_keys,
            self.mask,
        ];
        v.extend(self.focus);
        v.extend(self.spinner);
        v
    }
}

pub static UNICODE: Glyphs = Glyphs {
    cursor: "▶",
    dot: "●",
    ring: "○",
    rule: "─",
    path: "›",
    ellipsis: "…",
    separator: "·",
    bar: "━",
    track: "─",
    scroll: ["│", "┃"],
    ok: "✓",
    fail: "✕",
    skip: "·",
    up_down: "↑↓",
    enter: "⏎",
    page_keys: "⇞⇟",
    mask: "•",
    focus: &["░", "▒", "▓", "█"],
    spinner: &["◐", "◓", "◑", "◒"],
};

/// Linux console: every glyph is in the fonts iso/font.sh builds, checked by `make check`.
/// Terminus lacks ● ○ ✓ ✕ ⏎ ⇞⇟ and the spinner's quarter blocks.
pub static CONSOLE: Glyphs = Glyphs {
    cursor: "▶",
    dot: "■",
    ring: "·",
    rule: "─",
    path: "›",
    ellipsis: "…",
    separator: "·",
    bar: "█",
    track: "─",
    scroll: ["│", "█"],
    ok: "√",
    fail: "×",
    skip: "·",
    up_down: "↑↓",
    enter: "enter",
    page_keys: "pgup/pgdn",
    mask: "•",
    focus: &["░", "▒", "█"],
    spinner: &["│", "/", "─", "\\"],
};

/// xterm's sixteen stock colors. A themed console shows each slot in its own hue.
const STOCK: [(Color, Rgb); 16] = [
    (Color::Black, Rgb(0, 0, 0)),
    (Color::Red, Rgb(205, 0, 0)),
    (Color::Green, Rgb(0, 205, 0)),
    (Color::Yellow, Rgb(205, 205, 0)),
    (Color::Blue, Rgb(0, 0, 238)),
    (Color::Magenta, Rgb(205, 0, 205)),
    (Color::Cyan, Rgb(0, 205, 205)),
    (Color::Gray, Rgb(229, 229, 229)),
    (Color::DarkGray, Rgb(127, 127, 127)),
    (Color::LightRed, Rgb(255, 0, 0)),
    (Color::LightGreen, Rgb(0, 255, 0)),
    (Color::LightYellow, Rgb(255, 255, 0)),
    (Color::LightBlue, Rgb(92, 92, 255)),
    (Color::LightMagenta, Rgb(255, 0, 255)),
    (Color::LightCyan, Rgb(0, 255, 255)),
    (Color::White, Rgb(255, 255, 255)),
];

/// Nearest slot by RGB distance, where the product names none. Drawn from the slots a product
/// may name, so never the background or the muted text.
pub fn nearest(c: Rgb) -> Color {
    crate::spec::SLOTS
        .iter()
        .filter_map(|name| STOCK.iter().find(|(s, _)| Some(*s) == slot(name)))
        .min_by_key(|(_, s)| {
            let d = |a: u8, b: u8| (i32::from(a) - i32::from(b)).pow(2);
            d(c.0, s.0) + d(c.1, s.1) + d(c.2, s.2)
        })
        .map(|(slot, _)| *slot)
        .unwrap_or(Color::Cyan)
}

/// White or black, whichever contrasts more with the slot's stock color by WCAG.
fn contrast(slot: Color) -> Color {
    let Some((_, Rgb(r, g, b))) = STOCK.iter().find(|(c, _)| *c == slot) else {
        return Color::White;
    };
    let linear = |v: &u8| {
        let c = f64::from(*v) / 255.0;
        if c <= 0.04045 {
            c / 12.92
        } else {
            ((c + 0.055) / 1.055).powf(2.4)
        }
    };
    let lum = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
    if (lum + 0.05) / 0.05 > 1.05 / (lum + 0.05) {
        Color::Black
    } else {
        Color::White
    }
}

/// Slot by product name: the seven colors, then their bright variants.
pub fn slot(name: &str) -> Option<Color> {
    let i = crate::spec::SLOTS.iter().position(|s| *s == name)?;
    Some(STOCK[if i < 7 { i + 1 } else { i + 2 }].0)
}

impl Style {
    pub fn new(product: &crate::spec::Product, console: bool) -> Style {
        let accent = match (product.accent, console) {
            (Some(rgb), false) => Color::Rgb(rgb.0, rgb.1, rgb.2),
            (Some(rgb), true) => product
                .console_accent
                .as_deref()
                .and_then(slot)
                .unwrap_or_else(|| nearest(rgb)),
            (None, true) => product
                .console_accent
                .as_deref()
                .and_then(slot)
                .unwrap_or(Color::Cyan),
            (None, false) => Color::Cyan,
        };
        // A console background takes only the first eight colors, a bright one blinks or vanishes.
        // Blue unless the product names a slot.
        let selection = match (product.surface, console) {
            (Some(rgb), false) => Color::Rgb(rgb.0, rgb.1, rgb.2),
            (None, false) => Color::DarkGray,
            (_, true) => product
                .console_surface
                .as_deref()
                .and_then(slot)
                .unwrap_or(Color::Blue),
        };
        // On the console bold is the bright slot, and the accent's is about as bright as the
        // surface. The cursor row uses white or black there.
        let on_selection = if console { contrast(selection) } else { accent };
        Style {
            muted: Color::DarkGray,
            accent,
            selection,
            on_selection,
            success: Color::Green,
            warning: Color::Yellow,
            error: Color::Red,
            glyphs: if console { &CONSOLE } else { &UNICODE },
            dim_muted: console,
        }
    }

    pub fn color(&self, tone: Tone) -> Color {
        match tone {
            Tone::Normal => Color::Reset,
            Tone::Muted => self.muted,
            Tone::Accent => self.accent,
            Tone::Current => self.on_selection,
            Tone::Ok => self.success,
            Tone::Warn => self.warning,
            Tone::Error => self.error,
        }
    }

    pub fn base(&self) -> Cell {
        Cell::new().fg(Color::Reset).bg(Color::Reset)
    }

    pub fn tone(&self, tone: Tone) -> Cell {
        let cell = self.base().fg(self.color(tone));
        match tone == Tone::Muted && self.dim_muted {
            true => cell.add_modifier(Modifier::DIM),
            false => cell,
        }
    }

    /// Bold, except on the console, which draws bold as the bright slot, another color.
    pub fn bold(&self, tone: Tone) -> Cell {
        if self.dim_muted {
            return self.tone(tone);
        }
        self.tone(tone).add_modifier(Modifier::BOLD)
    }

    pub fn spinner(&self) -> &'static str {
        let frames = self.glyphs.spinner;
        let turns = super::beats(std::time::Instant::now(), super::BEAT) / 3;
        frames[turns as usize % frames.len()]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn product(console_accent: Option<&str>) -> crate::spec::Product {
        crate::spec::Product {
            title: "T".into(),
            accent: Some(Rgb(0x17, 0x93, 0xd1)),
            console_accent: console_accent.map(str::to_string),
            surface: Some(Rgb(0x3b, 0x42, 0x52)),
            console_surface: Some("blue".into()),
            logo: Vec::new(),
            status: None,
        }
    }

    #[test]
    fn the_accent_takes_the_slot_the_product_names_else_the_nearest() {
        assert_eq!(nearest(Rgb(0x20, 0xc0, 0x20)), Color::Green);
        assert_eq!(nearest(Rgb(0, 0, 0)), Color::Red, "never the field");
        assert_eq!(
            Style::new(&product(None), true).accent,
            Color::Cyan,
            "Arch blue sits between cyan and blue"
        );
        let console = Style::new(&product(Some("bright-blue")), true);
        assert_eq!(console.accent, Color::LightBlue);
        assert!(
            console
                .tone(Tone::Muted)
                .add_modifier
                .contains(Modifier::DIM)
        );
        assert!(
            !console
                .bold(Tone::Accent)
                .add_modifier
                .contains(Modifier::BOLD)
        );
        assert_eq!(console.selection, Color::Blue);
        assert_eq!(
            console.color(Tone::Current),
            Color::White,
            "the accent's slot reads badly on blue"
        );
        assert_eq!(
            contrast(Color::Gray),
            Color::Black,
            "and white on white not at all"
        );
        let terminal = Style::new(&product(Some("bright-blue")), false);
        assert_eq!(terminal.accent, Color::Rgb(0x17, 0x93, 0xd1));
        assert_eq!(terminal.selection, Color::Rgb(0x3b, 0x42, 0x52));
        assert_eq!(terminal.bold(Tone::Current), terminal.bold(Tone::Accent));
        assert_eq!(terminal.tone(Tone::Current), terminal.tone(Tone::Accent));
        assert!(
            terminal
                .bold(Tone::Normal)
                .add_modifier
                .contains(Modifier::BOLD)
        );
        assert_eq!(slot("green"), Some(Color::Green));
        assert_eq!(
            (slot("white"), slot("bright-red"), slot("bright-white")),
            (Some(Color::Gray), Some(Color::LightRed), Some(Color::White))
        );
    }

    #[test]
    fn nearest_picks_only_slots_a_product_may_name() {
        assert_eq!(nearest(Rgb(0x17, 0x93, 0xd1)), Color::Cyan);
        assert_eq!(nearest(Rgb(255, 255, 255)), Color::White);
        for c in [Rgb(0, 0, 0), Rgb(127, 127, 127), Rgb(110, 110, 110)] {
            let picked = nearest(c);
            assert!(
                crate::spec::SLOTS.iter().any(|s| slot(s) == Some(picked)),
                "{c:?} picked {picked:?}"
            );
        }
    }
}

//! Splash: the wordmark sweeps in above the version. Any key but a scroll ends it.

use std::time::{Duration, Instant};

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use crate::ui::draw::{put, width};
use crate::ui::{Ctx, Flow, Key, Page, Tone};

/// Splash and sweep duration: long enough to read as light passing through, short enough that
/// nobody waits.
const END: Duration = Duration::from_millis(1618);
pub const SWEEP: Duration = Duration::from_millis(382);
/// Columns behind the sweep front that still show a trace.
const TRAIL: f64 = 8.0;

pub struct SplashPage {
    started: Instant,
}

impl SplashPage {
    pub fn new() -> SplashPage {
        SplashPage {
            started: Instant::now(),
        }
    }

    /// State `ms` after the start.
    #[cfg(test)]
    pub fn after(ms: u64) -> SplashPage {
        SplashPage {
            started: Instant::now() - Duration::from_millis(ms),
        }
    }
}

/// Sweep progress from 0 to 1.
pub fn revealed(since: Duration) -> f64 {
    (since.as_secs_f64() / SWEEP.as_secs_f64()).min(1.0)
}

/// Centered wordmark from `y`, swept in by `revealed`, returning the next row. Lines above the
/// first blank one are the muted eyebrow.
pub fn wordmark(buf: &mut Buffer, area: Rect, y: u16, revealed: f64, ctx: &Ctx) -> u16 {
    let s = &ctx.style;
    let logo = &crate::spec::loaded().product.logo;
    let wide = logo.iter().map(|l| width(l)).max().unwrap_or(0);
    if wide == 0 || wide > area.width as usize || logo.len() as u16 > area.height {
        return y;
    }
    let x = area.x + (area.width - wide as u16) / 2;
    let eyebrow = logo.iter().position(|l| l.trim().is_empty()).unwrap_or(0);
    let front = revealed * wide as f64;
    let focus = s.glyphs.focus;
    for (i, line) in logo.iter().enumerate() {
        let tone = if i < eyebrow {
            Tone::Muted
        } else {
            Tone::Accent
        };
        let mut cx = x;
        for (dx, c) in line.chars().enumerate() {
            let w = width(&c.to_string()).max(1) as u16;
            if c != ' ' && (dx as f64) < front {
                let behind = ((front - dx as f64) / TRAIL).clamp(0.0, 1.0);
                let glyph = match c {
                    '█' if revealed < 1.0 => {
                        focus[((behind * (focus.len() - 1) as f64) + 0.5) as usize]
                    }
                    _ => {
                        &line[line.char_indices().nth(dx).map(|(i, _)| i).unwrap_or(0)..]
                            [..c.len_utf8()]
                    }
                };
                put(buf, cx, y + i as u16, glyph, w, s.bold(tone));
            }
            cx += w;
        }
    }
    y + logo.len() as u16
}

impl Page for SplashPage {
    fn unattended(&mut self, _: &mut Ctx) -> Result<Flow, String> {
        Ok(Flow::Pop)
    }

    fn title(&self) -> String {
        String::new()
    }

    fn bare(&self) -> bool {
        true
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        let since = self.started.elapsed();
        let rows = crate::spec::loaded().product.logo.len() as u16 + 2;
        let top = area.y + area.height.saturating_sub(rows) / 2;
        let under = wordmark(buf, area, top, revealed(since), ctx);
        if since >= SWEEP {
            let version = crate::version::version();
            crate::ui::draw::center(
                buf,
                area,
                under + 1,
                version,
                ctx.style.tone(Tone::Muted),
                "",
            );
        }
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, String)> {
        Vec::new()
    }

    fn key(&mut self, key: Key, _: &mut Ctx) -> Flow {
        match key {
            Key::WheelUp | Key::WheelDown => Flow::Stay,
            _ => Flow::Pop,
        }
    }

    fn tick(&mut self, _: &mut Ctx) -> Flow {
        if self.started.elapsed() >= END {
            Flow::Pop
        } else {
            Flow::Stay
        }
    }

    fn animating(&self, _: &Ctx) -> bool {
        true
    }

    fn pace(&self) -> Duration {
        crate::ui::FRAME
    }

    fn typing(&self) -> bool {
        true
    }
}

//! QR code of a value, to open a link on a phone. A slightly wrong code does not scan, so
//! colors, margin and whether to draw at all follow scanner needs.

use ratatui::style::{Color, Style as Cell};

/// Two stacked modules per cell keep modules square. All four glyphs are in codepage 437 and the
/// console fonts.
pub const CELLS: [&str; 4] = ["█", "▀", "▄", " "];

pub fn cell(upper: bool, lower: bool) -> &'static str {
    match (upper, lower) {
        (true, true) => CELLS[0],
        (true, false) => CELLS[1],
        (false, true) => CELLS[2],
        (false, false) => CELLS[3],
    }
}

/// Explicit black on white, since a scanner looks for dark squares on light.
pub fn ink() -> Cell {
    Cell::new().fg(Color::Black).bg(Color::White)
}

/// Quiet zone in modules: four per specification, two as scanners manage. The widest that fits
/// wins.
const QUIET: [usize; 3] = [4, 3, 2];

/// Rows of cells, or `None` where the code does not fit or encode. The page shows the value as
/// text either way.
pub fn code(text: &str, width: usize, height: usize) -> Option<Vec<String>> {
    if text.is_empty() {
        return None;
    }
    let code =
        qrcode::QrCode::with_error_correction_level(text.as_bytes(), qrcode::EcLevel::L).ok()?;
    let size = code.width();
    let quiet = QUIET
        .into_iter()
        .find(|q| size + 2 * q <= width && (size + 2 * q).div_ceil(2) <= height)?;
    let side = size + 2 * quiet;
    let dark = |x: usize, y: usize| {
        if x < quiet || y < quiet || x >= quiet + size || y >= quiet + size {
            return false;
        }
        code[(x - quiet, y - quiet)] == qrcode::Color::Dark
    };
    Some(
        (0..side)
            .step_by(2)
            .map(|y| {
                (0..side)
                    .map(|x| cell(dark(x, y), dark(x, y + 1)))
                    .collect()
            })
            .collect(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_code_is_square_in_modules_and_drops_its_margin_before_itself() {
        let rows = code("https://paste.rs/abcd", 80, 40).unwrap();
        let wide = rows[0].chars().count();
        assert_eq!(rows.len(), wide.div_ceil(2));
        assert!(rows[0].chars().all(|c| c == ' '), "a quiet row on top");
        let tight = code("https://paste.rs/abcd", wide - 2, 40).unwrap();
        assert_eq!(tight[0].chars().count(), wide - 2);
        assert!(code("https://paste.rs/abcd", 10, 40).is_none());
        assert!(code("", 80, 40).is_none());
    }
}

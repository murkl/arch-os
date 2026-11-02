//! One-line text box.

use ratatui::buffer::Buffer;

use super::draw::{cut_front, put, width};
use super::{Ctx, Key, Tone};

#[derive(Default)]
pub struct Input {
    pub text: String,
    pub masked: bool,
    pub placeholder: String,
}

impl Input {
    pub fn new(placeholder: &str) -> Input {
        Input {
            placeholder: placeholder.to_string(),
            ..Input::default()
        }
    }

    pub fn masked() -> Input {
        Input {
            masked: true,
            ..Input::default()
        }
    }

    /// Returns whether the key edited the text.
    pub fn key(&mut self, key: Key) -> bool {
        match key {
            Key::Char(c) if !c.is_control() => self.text.push(c),
            Key::Backspace => {
                self.text.pop();
            }
            Key::Ctrl('u') => self.text.clear(),
            Key::Ctrl('w') => {
                let kept = self.text.trim_end().rfind(' ').map_or(0, |i| i + 1);
                self.text.truncate(kept);
            }
            Key::AltBackspace if self.masked => self.text.clear(),
            Key::AltBackspace => {
                let word = self.text.trim_end_matches(|c: char| !c.is_alphanumeric());
                let kept = word.trim_end_matches(char::is_alphanumeric).len();
                self.text.truncate(kept);
            }
            _ => return false,
        }
        true
    }

    pub fn take(&mut self) -> String {
        std::mem::take(&mut self.text)
    }

    pub fn draw(&self, buf: &mut Buffer, x: u16, y: u16, w: u16, ctx: &Ctx) {
        let s = &ctx.style;
        let prompt = format!("{} ", s.glyphs.path);
        let after = put(buf, x, y, &prompt, w, s.bold(Tone::Accent));
        // One cell stays free for the cursor after the text.
        let room = w.saturating_sub(after - x + 1) as usize;
        if self.text.is_empty() {
            put(
                buf,
                after,
                y,
                &self.placeholder,
                room as u16,
                s.tone(Tone::Muted),
            );
            ctx.cursor.set(Some((after, y)));
            return;
        }
        let shown = if self.masked {
            s.glyphs.mask.repeat(self.text.chars().count())
        } else {
            self.text.clone()
        };
        let shown = cut_front(&shown, room, s.glyphs.ellipsis);
        let end = put(buf, after, y, &shown, room as u16, s.tone(Tone::Normal));
        if width(&shown) < room + 1 {
            ctx.cursor.set(Some((end, y)));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn edits_and_leaves_navigation_alone() {
        let mut i = Input::new("");
        for c in "pacman -S".chars() {
            assert!(i.key(Key::Char(c)));
        }
        assert!(i.key(Key::Ctrl('w')));
        assert_eq!(i.text, "pacman ");
        assert!(i.key(Key::Backspace));
        assert!(!i.key(Key::Up) && !i.key(Key::Enter) && !i.key(Key::Esc));
        assert_eq!(i.take(), "pacman");
    }

    /// Words of letters and digits, as readline's backward-kill-word and the zsh of Arch OS.
    #[test]
    fn alt_backspace_deletes_the_word_before_and_empties_a_password() {
        for (text, kept) in [
            ("gnome-extensions-app", "gnome-extensions-"),
            ("gnome-extensions-", "gnome-"),
            ("/usr/share/applications", "/usr/share/"),
            ("snake_case.txt", "snake_case."),
            ("pacman -S  ", "pacman -"),
            ("Grüße", ""),
        ] {
            let mut i = Input::new("");
            i.text = text.into();
            assert!(i.key(Key::AltBackspace));
            assert_eq!(i.text, kept, "{text}");
        }
        let mut p = Input::masked();
        p.text = "two words".into();
        assert!(p.key(Key::AltBackspace));
        assert_eq!(p.text, "", "no word boundary shows through the mask");
    }
}

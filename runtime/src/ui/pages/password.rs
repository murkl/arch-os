//! Password page: typed twice when new, once and checked when existing. The value reaches only
//! the script environment, never a file.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use super::Then;
use crate::i18n::t;
use crate::spec::{Kind, Setting};
use crate::ui::draw::{paragraph, put};
use crate::ui::input::Input;
use crate::ui::{Ctx, Data, Does, Flow, Key, Page, Tone};

pub struct PasswordPage {
    setting: &'static Setting,
    then: Then,
    input: Input,
    /// First entry while the repeat is typed.
    first: Option<String>,
    problem: Option<String>,
    /// The check runs, and the box ignores input until it answers.
    checking: bool,
}

/// Checked password and whether the check accepted it.
pub struct Tried(String, bool);

impl PasswordPage {
    pub fn new(setting: &'static Setting, then: Then) -> PasswordPage {
        PasswordPage {
            setting,
            then,
            input: Input::masked(),
            first: None,
            problem: None,
            checking: false,
        }
    }

    fn take(&mut self, value: String, ctx: &mut Ctx) -> Flow {
        ctx.store.set(&self.setting.name, &value);
        crate::info!("{}: given", self.setting.name);
        super::after(&self.then, ctx)
    }

    fn commit(&mut self, ctx: &mut Ctx) -> Flow {
        let value = self.input.take();
        match &self.first {
            None if value.is_empty() && self.setting.required => {
                self.problem = Some(t("An answer is required."));
                Flow::Stay
            }
            None if self.setting.kind == Kind::NewPassword => {
                self.first = Some(value);
                self.problem = None;
                Flow::Stay
            }
            // Start over, since there is no telling which entry was wrong.
            Some(first) if *first != value => {
                self.first = None;
                self.problem = Some(t("The two entries do not match."));
                Flow::Stay
            }
            // Accepted entry. The page resets in case back leads here again.
            _ => match &self.setting.check {
                Some(check) => {
                    self.first = None;
                    self.checking = true;
                    self.problem = None;
                    let mut env = ctx.env();
                    env.push((self.setting.name.clone(), value.clone()));
                    let check = check.clone();
                    ctx.spawn(move || {
                        let ok = crate::script::run(&check, &env)
                            .inspect_err(|e| crate::warn!("check: {e}"))
                            .is_ok();
                        Tried(value, ok)
                    });
                    Flow::Stay
                }
                None => {
                    self.first = None;
                    self.take(value, ctx)
                }
            },
        }
    }
}

impl Page for PasswordPage {
    /// Read from the environment under the setting's name, and checked like a typed one.
    fn unattended(&mut self, ctx: &mut Ctx) -> Result<Flow, String> {
        let name = self.setting.name.clone();
        let value = std::env::var(&name).unwrap_or_default();
        if value.is_empty() {
            return Err(crate::i18n::tf(
                "{{name}} is not set in the environment.",
                &[("name", &name)],
            ));
        }
        if let Some(check) = &self.setting.check {
            let mut env = ctx.env();
            env.push((name.clone(), value.clone()));
            crate::script::run(check, &env).map_err(|e| format!("{name}: {e}"))?;
        }
        Ok(self.take(value, ctx))
    }

    fn title(&self) -> String {
        t(&self.setting.title)
    }

    fn id(&self, _: &Ctx) -> String {
        let repeat = if self.first.is_some() { " repeat" } else { "" };
        format!("password {}{repeat}", self.setting.name)
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        let s = ctx.style;
        let mut y = area.y;
        let description = t(&self.setting.description);
        if !description.is_empty() {
            y = paragraph(buf, area, y, &description, s.tone(Tone::Muted)) + 1;
        }
        self.input.placeholder = if self.first.is_some() {
            t("Repeat")
        } else {
            t(&self.setting.title)
        };
        if self.checking {
            put(buf, area.x, y, s.spinner(), 2, s.tone(Tone::Accent));
            put(
                buf,
                area.x + 2,
                y,
                &t("Checking"),
                area.width.saturating_sub(2),
                s.tone(Tone::Muted),
            );
        } else {
            self.input.draw(buf, area.x, y, area.width, ctx);
        }
        if let Some(problem) = &self.problem {
            paragraph(buf, area, y + 2, problem, s.tone(Tone::Error));
        }
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, Does)> {
        let esc = if self.first.is_some() {
            Does::Return
        } else {
            Does::Back
        };
        vec![("⏎", Does::Answer), ("esc", esc)]
    }

    fn key(&mut self, key: Key, ctx: &mut Ctx) -> Flow {
        if self.checking {
            return match key {
                Key::Ctrl('c') => Flow::Ignored,
                _ => Flow::Stay,
            };
        }
        match key {
            Key::Enter => self.commit(ctx),
            // Esc on the repeat returns to the first entry, since both are one question.
            Key::Esc if self.first.is_some() => {
                self.first = None;
                self.problem = None;
                self.input = Input::masked();
                Flow::Stay
            }
            // Backing out forgets every password taken so far, so none stays in memory.
            Key::Esc | Key::Ctrl('c') => {
                ctx.store.forget();
                Flow::Ignored
            }
            k => {
                if self.input.key(k) {
                    self.problem = None;
                }
                Flow::Stay
            }
        }
    }

    fn data(&mut self, data: Data, ctx: &mut Ctx) -> Flow {
        let Data::Tried(tried) = data else {
            return Flow::Stay;
        };
        self.checking = false;
        if !tried.1 {
            self.problem = Some(match &self.setting.error {
                Some(e) => t(e),
                None => t("This password was not accepted."),
            });
            return Flow::Stay;
        }
        self.take(tried.0, ctx)
    }

    fn typing(&self) -> bool {
        true
    }

    fn animating(&self, _: &Ctx) -> bool {
        self.checking
    }

    fn root(&self) -> bool {
        matches!(self.then, Then::Opening | Then::Start)
    }
}

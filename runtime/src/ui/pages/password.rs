//! A value never written down: typed twice where it is chosen, once where it exists and is tried
//! on what it opens. It reaches the environment of the scripts and nothing else.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use super::Then;
use crate::i18n::t;
use crate::spec::{Kind, Setting};
use crate::ui::draw::{paragraph, put};
use crate::ui::input::Input;
use crate::ui::{Ctx, Data, Flow, Key, Page, Tone};

pub struct PasswordPage {
    setting: &'static Setting,
    then: Then,
    input: Input,
    /// The first entry, while the repeat is typed.
    first: Option<String>,
    problem: Option<String>,
    /// The check runs, and the box takes nothing until it has answered.
    checking: bool,
}

/// What the module's check made of the password.
/// A password tried on the machine: the value, and whether it was taken.
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
            // Back to the beginning: one of the two was wrong, and there is no telling which.
            Some(first) if *first != value => {
                self.first = None;
                self.problem = Some(t("The two entries do not match."));
                Flow::Stay
            }
            // Taken, and the page fresh again should the way back lead to it.
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
    /// From the environment, under the setting's own name, and tried on the machine as a
    /// typed one is.
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

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        let s = ctx.style;
        let mut y = area.y;
        let description = t(&self.setting.description);
        if !description.is_empty() {
            y = paragraph(buf, area, y, &description, s.tone(Tone::Muted)) + 1;
        }
        // The box names what goes in it, the second time the repeat.
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

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, String)> {
        vec![("⏎", t("confirm")), ("esc", t("back"))]
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
            // Backing out of the repeat goes back to the first entry: the two are one question.
            Key::Esc if self.first.is_some() => {
                self.first = None;
                self.problem = None;
                self.input = Input::masked();
                Flow::Stay
            }
            // Backing out forgets what the chain has taken so far: the next start asks for all
            // of it again, and none of it stays in memory meanwhile.
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

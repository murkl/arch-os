//! Requirements gate: checks in order and stops on the first failure, rechecking every few
//! seconds. Enter opens that action's fallback.

use std::time::{Duration, Instant};

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use crate::i18n::t;
use crate::spec::{Action, Shell};
use crate::ui::draw::{paragraph, put, waiting};
use crate::ui::{Ctx, Data, Does, Flow, Key, Page, Tone};

/// Recheck interval: short enough that a plugged-in cable passes before anyone presses r, long
/// enough that a network check is no load.
const EVERY: Duration = Duration::from_secs(5);

pub struct GatePage {
    at: usize,
    /// The current check failed, with its fallback where this machine has one.
    refused: Option<Option<&'static Action>>,
    checking: bool,
    /// Current round. Results of an older one are ignored.
    round: u64,
    asked: Instant,
    /// The fallback opened by itself once. Reopening it on every return would make the gate
    /// unreachable.
    opened: bool,
}

pub struct Said {
    round: u64,
    yes: bool,
    fallback: Option<&'static Action>,
    /// The check's own words on a no, for the log. The page shows the module's.
    why: String,
}

impl GatePage {
    pub fn new() -> GatePage {
        GatePage {
            at: 0,
            refused: None,
            checking: false,
            round: 0,
            asked: Instant::now(),
            opened: false,
        }
    }

    fn action(&self, ctx: &Ctx) -> &'static Action {
        ctx.module.named(&ctx.module.requires)[self.at]
    }

    /// Starts a new round for the current check and its fallback's availability.
    fn check(&mut self, ctx: &mut Ctx) {
        self.round += 1;
        self.checking = true;
        self.asked = Instant::now();
        let round = self.round;
        let action = self.action(ctx);
        let env = ctx.env();
        let fallbacks: Vec<(&'static Action, Vec<Shell>)> = ctx
            .module
            .named(&action.on_failure)
            .into_iter()
            .map(|fb| {
                (
                    fb,
                    ctx.module
                        .named(&fb.requires)
                        .iter()
                        .map(|a| a.run.clone())
                        .collect(),
                )
            })
            .collect();
        let run = action.run.clone();
        ctx.spawn(move || {
            let why = match crate::script::guard(&run, &env) {
                Ok(()) => {
                    return Said {
                        round,
                        yes: true,
                        fallback: None,
                        why: String::new(),
                    };
                }
                Err(why) => why,
            };
            let fallback = fallbacks
                .into_iter()
                .find(|(_, checks)| checks.iter().all(|c| crate::script::guard(c, &env).is_ok()))
                .map(|(fb, _)| fb);
            Said {
                round,
                yes: false,
                fallback,
                why,
            }
        });
    }
}

impl Page for GatePage {
    /// A failure is final, since nobody is there to plug in a cable.
    fn unattended(&mut self, ctx: &mut Ctx) -> Result<Flow, String> {
        if self.refused.is_none() {
            return Ok(Flow::Stay);
        }
        let action = self.action(ctx);
        Err(ctx.expand(&t(action.error.as_deref().unwrap_or_default())))
    }

    fn title(&self) -> String {
        String::new()
    }

    fn id(&self, ctx: &Ctx) -> String {
        format!("gate {}", self.action(ctx).id)
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        if self.round == 0 {
            self.check(ctx);
        }
        let s = ctx.style;
        let action = self.action(ctx);
        let Some(fallback) = &self.refused else {
            waiting(buf, area, &t(&action.title), None, ctx);
            return;
        };
        let why = ctx.expand(&t(action.error.as_deref().unwrap_or_default()));
        put(buf, area.x, area.y, s.glyphs.fail, 1, s.tone(Tone::Error));
        let text = Rect::new(
            area.x + 2,
            area.y,
            area.width.saturating_sub(2),
            area.height,
        );
        let y = paragraph(buf, text, area.y, &why, s.bold(Tone::Normal));
        if let Some(fb) = fallback {
            paragraph(buf, text, y + 1, &t(&fb.description), s.tone(Tone::Muted));
        }
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, Does)> {
        match &self.refused {
            None => Vec::new(),
            Some(Some(_)) => vec![("⏎", Does::Open), ("r", Does::Reload), ("esc", Does::Back)],
            Some(None) => vec![("r", Does::Reload), ("esc", Does::Back)],
        }
    }

    fn key(&mut self, key: Key, ctx: &mut Ctx) -> Flow {
        let Some(fallback) = self.refused else {
            return match key {
                Key::Esc | Key::Ctrl('c') => Flow::Ignored,
                _ => Flow::Stay,
            };
        };
        match key {
            Key::Enter => match fallback {
                Some(fallback) => super::action::open(ctx, fallback, false),
                None => Flow::Stay,
            },
            Key::Char('r') => {
                self.check(ctx);
                Flow::Stay
            }
            Key::Esc | Key::Backspace | Key::Ctrl('c') | Key::Char('q') => Flow::Ignored,
            _ => Flow::Stay,
        }
    }

    fn data(&mut self, data: Data, ctx: &mut Ctx) -> Flow {
        let Data::Said(said) = data else {
            return Flow::Stay;
        };
        if said.round != self.round {
            return Flow::Stay;
        }
        self.checking = false;
        if said.yes {
            self.refused = None;
            self.opened = false;
            if self.at + 1 < ctx.module.requires.len() {
                self.at += 1;
                self.check(ctx);
                return Flow::Stay;
            }
            ctx.gated = true;
            return match super::next(ctx) {
                Flow::Push(page) => Flow::Replace(page),
                flow => flow,
            };
        }
        crate::info!("{} said no: {}", self.action(ctx).id, said.why);
        self.refused = Some(said.fallback);
        // A fallback with questions opens at once. One that would run waits for enter as consent.
        if let Some(fb) = said.fallback
            && !self.opened
            && !fb.inputs.is_empty()
        {
            self.opened = true;
            return super::action::open(ctx, fb, false);
        }
        Flow::Stay
    }

    fn tick(&mut self, ctx: &mut Ctx) -> Flow {
        if self.refused.is_some() && !self.checking && self.asked.elapsed() >= EVERY {
            self.check(ctx);
        }
        Flow::Stay
    }

    fn root(&self) -> bool {
        true
    }

    fn resumed(&mut self, ctx: &mut Ctx) -> Flow {
        self.check(ctx);
        Flow::Stay
    }

    fn animating(&self, _: &Ctx) -> bool {
        self.checking || self.refused.is_some()
    }

    fn pace(&self) -> Duration {
        if self.checking {
            crate::ui::BEAT
        } else {
            Duration::from_millis(500)
        }
    }
}

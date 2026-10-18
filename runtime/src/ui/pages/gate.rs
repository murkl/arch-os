//! What the work requires, asked in order. The page stands on the first no, asking again every
//! few seconds, with enter opening what that action falls back on.

use std::time::{Duration, Instant};

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use crate::i18n::t;
use crate::spec::Action;
use crate::ui::draw::{paragraph, put, waiting};
use crate::ui::{Ctx, Data, Flow, Key, Page, Tone};

/// How often the page asks again by itself: often enough that a cable plugged in carries on
/// before anybody reaches for r, rarely enough that a check going out to the network is no load.
const EVERY: Duration = Duration::from_secs(5);

pub struct GatePage {
    at: usize,
    /// The action standing now said no, and what it falls back on where this machine has it.
    refused: Option<Option<&'static Action>>,
    checking: bool,
    /// Which check still counts: a clock set before the page moved on is ignored.
    round: u64,
    asked: Instant,
    /// The fallback was opened by itself once. Every time the page comes back would be a page
    /// nobody can get to.
    opened: bool,
}

pub struct Said {
    round: u64,
    yes: bool,
    fallback: Option<&'static Action>,
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

    /// Asks the action standing now, as a new round, and whether this machine has what it falls
    /// back on.
    fn check(&mut self, ctx: &mut Ctx) {
        self.round += 1;
        self.checking = true;
        self.asked = Instant::now();
        let round = self.round;
        let action = self.action(ctx);
        let env = ctx.env();
        let fallbacks: Vec<(&'static Action, Vec<String>)> = ctx
            .module
            .named(&action.on_failure)
            .into_iter()
            .map(|fb| {
                (
                    fb,
                    ctx.module
                        .named(&fb.requires)
                        .iter()
                        .map(|a| a.script())
                        .collect(),
                )
            })
            .collect();
        let script = action.script();
        ctx.spawn(move || {
            if crate::script::guard(&script, &env).is_ok() {
                return Said {
                    round,
                    yes: true,
                    fallback: None,
                };
            }
            let fallback = fallbacks
                .into_iter()
                .find(|(_, checks)| checks.iter().all(|c| crate::script::guard(c, &env).is_ok()))
                .map(|(fb, _)| fb);
            Said {
                round,
                yes: false,
                fallback,
            }
        });
    }
}

impl Page for GatePage {
    fn title(&self) -> String {
        String::new()
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

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, String)> {
        match &self.refused {
            None => Vec::new(),
            Some(Some(_)) => vec![("⏎", t("open")), ("r", t("try again")), ("esc", t("back"))],
            Some(None) => vec![("r", t("try again")), ("esc", t("back"))],
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
        crate::info!("{} said no", self.action(ctx).id);
        self.refused = Some(said.fallback);
        // A fallback that asks first opens at once; one that would run waits for enter, which is
        // the consent.
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

//! The way out where the module says how the machine is put down: its rows, and under them
//! closing the program, which a kiosk starts again. Opened over what was happening, it stops
//! nothing until a row is chosen.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use crate::i18n::t;
use crate::script::{self, Event, Session};
use crate::spec::Action;
use crate::ui::detail::{Detail, failure};
use crate::ui::draw::{paragraph, waiting};
use crate::ui::list::{List, Picked, Row};
use crate::ui::{Ctx, Flow, Key, Page, Tone};

/// What a row does: an action of the module, or closing the program.
#[derive(Clone, Copy, Debug, PartialEq)]
enum Way {
    Action(&'static Action),
    Exit,
}

/// The keys on the bare page, in no language in particular, like the first page's.
const KEYS: &str = "↑↓ move · ⏎ confirm · esc back";

pub struct LeavePage {
    list: List<Way>,
    /// A run goes on behind this page, which every row stops.
    running: bool,
    /// Opened over the first page, before there is a frame: drawn like it.
    bare: bool,
    /// The action under way: a restart takes a moment to arrive, and the page says so.
    doing: Option<(&'static Action, Option<Session>)>,
    failed: Option<Detail>,
}

impl LeavePage {
    pub fn new(ctx: &Ctx, running: bool, bare: bool) -> LeavePage {
        let mut rows: Vec<Row<Way>> = ctx
            .rows(&ctx.module.on.leave)
            .into_iter()
            .map(|a| Row::new(Way::Action(a), t(&a.title)).describe(t(&a.description)))
            .collect();
        let (title, help) = if ctx.kiosk {
            (
                t("Start over"),
                t("Starts this program again from the beginning. Every answer is kept."),
            )
        } else {
            (
                t("Exit"),
                t("Closes this program. The machine keeps running."),
            )
        };
        rows.push(Row::new(Way::Exit, title).describe(help));
        let mut list = List::new(rows);
        list.described = !bare;
        LeavePage {
            list,
            running,
            bare,
            doing: None,
            failed: None,
        }
    }

    /// Does what a row stands for. From here on this is a decision rather than a question, so
    /// whatever was running behind this page is put down first.
    fn carry_out(&mut self, way: Way, ctx: &mut Ctx) -> Flow {
        ctx.halt = true;
        let Way::Action(action) = way else {
            crate::info!("exit");
            return Flow::Quit;
        };
        crate::info!("action {}", action.id);
        if ctx.store.dry_run() && !action.simulates {
            return Flow::Quit;
        }
        let step = ctx.step(&t(&action.title), true, action.script());
        match script::start(step, &ctx.env(), ctx.run_sink()) {
            Ok(session) => {
                self.doing = Some((action, Some(session)));
                Flow::Stay
            }
            Err(e) => {
                crate::error!("action {}: {e}", action.id);
                Flow::Quit
            }
        }
    }
}

impl Page for LeavePage {
    fn title(&self) -> String {
        t("Leave")
    }

    fn leaving(&self) -> bool {
        true
    }

    fn bare(&self) -> bool {
        self.bare
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        if let Some((action, _)) = &self.doing {
            waiting(buf, area, &t(&action.title), None, ctx);
            return;
        }
        if self.bare && self.failed.is_none() {
            super::language::bare(buf, area, ctx, None, &mut self.list, KEYS);
            return;
        }
        let mut y = area.y;
        if let Some(failed) = &mut self.failed {
            let height = failed
                .height(area.width, ctx)
                .min(area.height.saturating_sub(5));
            failed.draw(Rect::new(area.x, y, area.width, height), buf, ctx);
            y += height + 1;
        }
        if self.running {
            y = paragraph(
                buf,
                area,
                y,
                &t("The run goes on behind this page. Every choice here stops it."),
                ctx.style.tone(Tone::Warn),
            ) + 1;
        }
        self.list.draw(
            Rect::new(area.x, y, area.width, area.bottom().saturating_sub(y)),
            buf,
            ctx,
        );
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, String)> {
        if self.doing.is_some() {
            return Vec::new();
        }
        vec![("↑↓", t("choose")), ("⏎", t("confirm")), ("esc", t("back"))]
    }

    fn key(&mut self, key: Key, ctx: &mut Ctx) -> Flow {
        // Nothing means anything while the machine is going down.
        if self.doing.is_some() {
            return Flow::Stay;
        }
        match self.list.key(key) {
            Picked::Open(way) => self.carry_out(way, ctx),
            Picked::Used => Flow::Stay,
            Picked::Ignored if matches!(key, Key::Esc | Key::Backspace | Key::Char('q')) => {
                Flow::Pop
            }
            Picked::Ignored => Flow::Ignored,
        }
    }

    fn run(&mut self, event: Event, _: &mut Ctx) -> Flow {
        let Event::Exit(result) = event else {
            return Flow::Stay;
        };
        self.doing = None;
        match result {
            // A machine going down takes the program with it long before: this is a module tried
            // out, and the program closes.
            Ok(()) => Flow::Quit,
            Err(f) => {
                crate::error!("{f}");
                let mut detail = Detail::default();
                detail.set(failure(&f), Vec::new());
                self.failed = Some(detail);
                Flow::Stay
            }
        }
    }

    fn stop(&mut self) {
        if let Some((_, Some(session))) = &self.doing {
            session.kill();
        }
    }

    fn animating(&self, _: &Ctx) -> bool {
        self.doing.is_some()
    }
}

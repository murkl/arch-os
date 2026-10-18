//! The way out where the module says how the machine is put down: its rows, and under them
//! closing the program, which a kiosk starts again. Opened over what was happening, it stops
//! nothing until a row is chosen, and carries the row out once what ran has stopped.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use crate::i18n::t;
use crate::script::{self, Event, Session};
use crate::spec::Action;
use crate::ui::detail::{Detail, failure};
use crate::ui::draw::{paragraph, waiting};
use crate::ui::list::{List, Picked, Row};
use crate::ui::{Ctx, Data, Flow, Key, Page, Tone};

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
    /// Opened over the first page, before there is a frame: drawn like it.
    bare: bool,
    /// The row chosen, and its action's script once what ran behind has stopped: a restart takes
    /// a moment to arrive, and the page says so.
    doing: Option<(Way, Option<Session>)>,
    failed: Option<Detail>,
}

impl LeavePage {
    pub fn new(ctx: &Ctx, bare: bool) -> LeavePage {
        let mut rows: Vec<Row<Way>> = ctx
            .rows(&ctx.module.on.leave)
            .into_iter()
            .map(|a| {
                Row::new(Way::Action(a), label(Way::Action(a), ctx)).describe(t(&a.description))
            })
            .collect();
        let help = if ctx.kiosk {
            t("Restarts this program. All answers are kept.")
        } else {
            t("Closes this program. The machine keeps running.")
        };
        rows.push(Row::new(Way::Exit, label(Way::Exit, ctx)).describe(help));
        let mut list = List::new(rows);
        list.described = !bare;
        LeavePage {
            list,
            bare,
            doing: None,
            failed: None,
        }
    }

    /// From here on a row is a decision rather than a question: whatever runs behind this page
    /// is stopped first, and the row is carried out once it has.
    fn decide(&mut self, way: Way, ctx: &mut Ctx) -> Flow {
        self.doing = Some((way, None));
        self.failed = None;
        ctx.halt = Some(ctx.page_id());
        Flow::Stay
    }

    /// Does what the row stands for, nothing running behind this page any more.
    fn carry_out(&mut self, way: Way, ctx: &mut Ctx) -> Flow {
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
                self.doing = Some((way, Some(session)));
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
        if let Some((way, _)) = self.doing {
            waiting(buf, area, &label(way, ctx), None, ctx);
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
        if ctx.behind {
            y = paragraph(
                buf,
                area,
                y,
                &t("The run continues in the background. Any choice here stops it."),
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
            Picked::Open(way) => self.decide(way, ctx),
            Picked::Used => Flow::Stay,
            Picked::Ignored if matches!(key, Key::Esc | Key::Backspace | Key::Char('q')) => {
                Flow::Pop
            }
            Picked::Ignored => Flow::Ignored,
        }
    }

    fn data(&mut self, data: Data, ctx: &mut Ctx) -> Flow {
        match (data, &self.doing) {
            (Data::Halted, Some((way, None))) => {
                let way = *way;
                self.carry_out(way, ctx)
            }
            _ => Flow::Stay,
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

    fn stop(&mut self, _: &mut Ctx) -> Option<Session> {
        self.doing.as_mut().and_then(|(_, session)| session.take())
    }

    fn animating(&self, _: &Ctx) -> bool {
        self.doing.is_some()
    }
}

/// A row's name, which the page also stands under while the row is carried out.
fn label(way: Way, ctx: &Ctx) -> String {
    match way {
        Way::Action(action) => t(&action.title),
        Way::Exit if ctx.kiosk => t("Start over"),
        Way::Exit => t("Exit"),
    }
}

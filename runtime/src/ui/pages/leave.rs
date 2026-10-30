//! Leave page: the module's shutdown rows, then closing the program, which a kiosk restarts.
//! Nothing stops until a row is chosen, and the row runs once everything behind has stopped. A
//! running run leads with the way back to it, so enter alone stops nothing.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use crate::i18n::t;
use crate::script::{self, Event, Session};
use crate::spec::Action;
use crate::ui::detail::{Detail, failure};
use crate::ui::draw::{paragraph, waiting};
use crate::ui::list::{List, Picked, Row};
use crate::ui::{Ctx, Data, Does, Flow, Key, Page, Tone};

#[derive(Clone, Copy, Debug, PartialEq)]
enum Way {
    Back,
    Action(&'static Action),
    Exit,
}

/// Keys of the bare page, in English like the language page's, which is all it opens over.
const KEYS: &[(&str, Does)] = &[("↑↓", Does::Choose), ("⏎", Does::Run), ("esc", Does::Back)];

pub struct LeavePage {
    list: List<Way>,
    /// Opened over the bare first page, so drawn bare too.
    bare: bool,
    /// Chosen row, and its script once everything behind has stopped. A restart takes a moment, so
    /// the page shows it.
    doing: Option<(Way, Option<Session>)>,
    failed: Option<Detail>,
}

impl LeavePage {
    pub fn new(ctx: &Ctx, bare: bool, running: bool) -> LeavePage {
        let mut rows: Vec<Row<Way>> = Vec::new();
        if running {
            rows.push(Row::new(Way::Back, label(Way::Back, ctx)));
        }
        rows.extend(ctx.rows(&ctx.module.on.leave).into_iter().map(|a| {
            Row::new(Way::Action(a), label(Way::Action(a), ctx)).describe(t(&a.description))
        }));
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

    /// Stops everything behind this page first, then carries out the row.
    fn decide(&mut self, way: Way, ctx: &mut Ctx) -> Flow {
        self.doing = Some((way, None));
        self.failed = None;
        ctx.halt = Some(ctx.page_id());
        Flow::Stay
    }

    /// Runs the row, with nothing left running behind this page.
    fn carry_out(&mut self, way: Way, ctx: &mut Ctx) -> Flow {
        let Way::Action(action) = way else {
            crate::info!("exit");
            return Flow::Quit;
        };
        crate::info!("action {}", action.id);
        if ctx.store.dry_run() && !action.simulates {
            return Flow::Quit;
        }
        let step = ctx.step(&t(&action.title), true, action.run.clone());
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

    fn id(&self, _: &Ctx) -> String {
        "leave".into()
    }

    fn focus(&self) -> Option<String> {
        Some(match self.list.selected()?.id? {
            Way::Back => "back".into(),
            Way::Action(action) => action.id.clone(),
            Way::Exit => "exit".into(),
        })
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

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, Does)> {
        if self.doing.is_some() {
            return Vec::new();
        }
        let enter = match self.list.selected().and_then(|r| r.id) {
            Some(Way::Back) => Does::Back,
            _ => Does::Run,
        };
        vec![("↑↓", Does::Choose), ("⏎", enter), ("esc", Does::Back)]
    }

    fn key(&mut self, key: Key, ctx: &mut Ctx) -> Flow {
        // Keys do nothing while the machine goes down.
        if self.doing.is_some() {
            return Flow::Stay;
        }
        match self.list.key(key) {
            Picked::Open(Way::Back) => Flow::Pop,
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
            // A real shutdown ends the program before this. Here a module is being tried out, so
            // the program quits.
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

/// Row name, also the page title while the row runs.
fn label(way: Way, ctx: &Ctx) -> String {
    match way {
        Way::Back => t("Back to the run"),
        Way::Action(action) => t(&action.title),
        Way::Exit if ctx.kiosk => t("Start over"),
        Way::Exit => t("Exit"),
    }
}

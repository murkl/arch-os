//! The dashboard: the row that starts the work, every answer under its heading, and under those
//! the language, what the module offers here and the reset. Every row opens a page.

use crate::spec::{Action, Setting};
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use super::Then;
use crate::i18n::t;
use crate::ui::list::{List, Picked, Row, hints};
use crate::ui::{Ctx, Data, Flow, Key, Page, Tone};

/// What a row opens.
#[derive(Clone, Copy, Debug)]
enum Item {
    Start,
    Setting(&'static Setting),
    Language,
    Action(&'static Action),
    Reset,
}

/// Two rows mean the same where they name the same declaration.
impl PartialEq for Item {
    fn eq(&self, other: &Item) -> bool {
        match (self, other) {
            (Item::Setting(a), Item::Setting(b)) => std::ptr::eq(*a, *b),
            (Item::Action(a), Item::Action(b)) => std::ptr::eq(*a, *b),
            (a, b) => std::mem::discriminant(a) == std::mem::discriminant(b),
        }
    }
}

pub struct DashboardPage {
    list: List<Item>,
    /// The opening ran once this page was reached.
    opened: bool,
    /// The lists the answers were chosen from are read again, before the work starts.
    checking: bool,
}

/// The answers no list offers any more.
pub struct Unoffered(Vec<String>);

impl DashboardPage {
    pub fn new() -> DashboardPage {
        DashboardPage {
            list: List::default(),
            opened: false,
            checking: false,
        }
    }

    fn rows(&self, ctx: &Ctx) -> Vec<Row<Item>> {
        let s = &ctx.style;
        let mut rows = vec![Row::new(Item::Start, t(&ctx.module.start))];
        if self.checking {
            rows[0].detail = s.spinner().to_string();
            rows[0].tone = Tone::Accent;
        }
        let mut group = "";
        for setting in ctx.store.visible() {
            if setting.group != group {
                group = &setting.group;
                rows.push(Row::heading(t(group)));
            }
            rows.push(
                Row::new(Item::Setting(setting), t(&setting.title))
                    .detail(ctx.store.display(setting), Tone::Muted),
            );
        }
        rows.push(Row::heading(""));
        rows.push(
            Row::new(Item::Language, t("Interface language"))
                .detail(&crate::i18n::current().name, Tone::Muted),
        );
        for action in ctx.rows(&ctx.module.on.dashboard) {
            rows.push(Row::new(Item::Action(action), t(&action.title)));
        }
        rows.push(Row::new(Item::Reset, t("Reset all answers")));
        rows
    }

    /// Reads every list an answer was chosen from once more, right before the work: an answer
    /// file from another machine names its disks, and the list is the rule. A list that also
    /// takes a typed answer vouches neither way.
    fn begin(&mut self, ctx: &mut Ctx) {
        self.checking = true;
        let env = ctx.env();
        let held: Vec<(String, String, crate::spec::Shell)> = ctx
            .store
            .visible()
            .into_iter()
            .filter(|s| s.kind == crate::spec::Kind::List && !ctx.store.get(&s.name).is_empty())
            .filter_map(|s| {
                s.options_from
                    .clone()
                    .map(|from| (s.name.clone(), ctx.store.get(&s.name).to_string(), from))
            })
            .collect();
        ctx.spawn(move || {
            let mut out = Vec::new();
            for (name, value, from) in held {
                match crate::script::lines(&from, &env) {
                    Ok(lines) => {
                        if !lines
                            .iter()
                            .any(|l| l.split('\t').next().unwrap_or_default().trim() == value)
                        {
                            crate::info!("{name}: {value} is not among the answers offered");
                            out.push(name);
                        }
                    }
                    Err(e) => crate::warn!("options for {name}: {e}"),
                }
            }
            Unoffered(out)
        });
    }
}

impl Page for DashboardPage {
    fn title(&self) -> String {
        String::new()
    }

    fn home(&self) -> bool {
        true
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        let rows = self.rows(ctx);
        self.list.set(rows);
        self.list.draw(area, buf, ctx);
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, String)> {
        if self.list.typing() {
            return hints(true);
        }
        vec![
            ("↑↓", t("choose")),
            ("⏎", t("open")),
            ("f", t("filter")),
            ("q", t("quit")),
        ]
    }

    fn key(&mut self, key: Key, ctx: &mut Ctx) -> Flow {
        if self.checking {
            return match key {
                Key::Ctrl('c') => Flow::Ignored,
                _ => Flow::Stay,
            };
        }
        match self.list.key(key) {
            Picked::Open(Item::Start) => {
                self.begin(ctx);
                Flow::Stay
            }
            Picked::Open(Item::Setting(s)) => Flow::Push(Box::new(
                super::question::QuestionPage::setting(s, Then::Pop),
            )),
            Picked::Open(Item::Language) => {
                Flow::Push(Box::new(super::language::LangPage::new(Then::Pop)))
            }
            Picked::Open(Item::Action(action)) => super::action::open(ctx, action, false),
            Picked::Open(Item::Reset) => Flow::Push(Box::new(super::confirm::YesNoPage::reset())),
            Picked::Used => Flow::Stay,
            Picked::Ignored => Flow::Ignored,
        }
    }

    fn data(&mut self, data: Data, ctx: &mut Ctx) -> Flow {
        let Data::Unoffered(unoffered) = data else {
            return Flow::Stay;
        };
        self.checking = false;
        for name in unoffered.0 {
            ctx.store.unoffer(&name);
        }
        super::start(ctx)
    }

    /// Back on top: a card is a thing that gets plugged in, so which actions this machine has is
    /// asked again, and the first time here the opening runs.
    fn resumed(&mut self, ctx: &mut Ctx) -> Flow {
        ctx.look();
        if !self.opened {
            self.opened = true;
            return super::next(ctx);
        }
        Flow::Stay
    }

    fn typing(&self) -> bool {
        self.list.typing()
    }

    fn animating(&self, _: &Ctx) -> bool {
        self.checking
    }
}

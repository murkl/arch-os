//! Dashboard: start row, answers under their headings, actions and reset, in module order.
//! Every row opens a page.

use crate::spec::{Action, Entry, Setting};
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use super::Then;
use crate::i18n::t;
use crate::ui::list::{List, Picked, Row};
use crate::ui::{Ctx, Data, Does, Flow, Key, Page, Tone};

/// What a row opens.
#[derive(Clone, Copy, Debug)]
enum Item {
    Start,
    Setting(&'static Setting),
    Language,
    Action(&'static Action),
    Reset,
}

/// Rows are equal when they name the same declaration.
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
    /// The opening ran, on the first return to this page.
    opened: bool,
    /// Rereading the answers' option lists before the run.
    checking: bool,
}

/// Answers missing from their reread option list.
pub struct Unoffered(Vec<String>);

/// Visible answers under their group headings, the language first under the heading the module
/// names, shown even with its group hidden. Also returns the last group.
fn answers(ctx: &Ctx) -> (Vec<Row<Item>>, Option<&'static str>) {
    let language = || {
        Row::new(Item::Language, t("Interface language"))
            .detail(&crate::i18n::current().name, Tone::Muted)
    };
    let home = ctx.module.language.as_deref();
    let mut rows = Vec::new();
    let mut group = "";
    let mut placed = false;
    for setting in ctx.store.visible() {
        if setting.group != group {
            group = &setting.group;
            rows.push(Row::heading(t(group)));
            if home == Some(group) {
                rows.push(language());
                placed = true;
            }
        }
        rows.push(
            Row::new(Item::Setting(setting), t(&setting.title))
                .detail(ctx.store.display(setting), Tone::Muted),
        );
    }
    if let Some(home) = home.filter(|_| !placed) {
        group = home;
        rows.push(Row::heading(t(home)));
        rows.push(language());
    }
    (rows, Some(group).filter(|g| !g.is_empty()))
}

impl DashboardPage {
    pub fn new() -> DashboardPage {
        DashboardPage {
            list: List::filterable(Vec::new()),
            opened: false,
            checking: false,
        }
    }

    /// Blank rows separate the start, the answers and each action group, except right before
    /// headed answers. Consecutive actions of a group share one heading, a blank row right under
    /// answers ending in that group.
    fn rows(&self, ctx: &Ctx) -> Vec<Row<Item>> {
        let mut rows = Vec::new();
        let mut gap = false;
        let mut under: Option<&str> = None;
        let mut ends: Option<&str> = None;
        for entry in &ctx.module.dashboard {
            let mut group = None;
            let (block, last) = match entry {
                Entry::Start => (vec![self.start(ctx)], None),
                Entry::Settings => answers(ctx),
                Entry::Reset => (vec![Row::new(Item::Reset, t("Reset all answers"))], None),
                Entry::Action(name) => (
                    ctx.rows(std::slice::from_ref(name))
                        .into_iter()
                        .map(|a| {
                            group = a.group.as_deref();
                            Row::new(Item::Action(a), t(&a.title))
                        })
                        .collect(),
                    None,
                ),
            };
            if block.is_empty() {
                continue;
            }
            match group {
                Some(g) if ends == Some(g) => rows.push(Row::heading("")),
                Some(g) if under != Some(g) => rows.push(Row::heading(t(g))),
                Some(_) => {}
                None if gap && *entry != Entry::Settings => rows.push(Row::heading("")),
                None => {}
            }
            rows.extend(block);
            under = group;
            ends = last;
            gap = group.is_some() || matches!(entry, Entry::Start | Entry::Settings);
        }
        rows
    }

    fn start(&self, ctx: &Ctx) -> Row<Item> {
        let mut row = Row::new(Item::Start, t(&ctx.module.start));
        if self.checking {
            row.detail = ctx.style.spinner().to_string();
            row.tone = Tone::Accent;
        }
        row
    }

    /// Rereads each chosen option list right before the run, since an answer file from another
    /// machine names its disks. A list that also takes typed answers is skipped.
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
    /// Starts the run, as the first row does.
    fn unattended(&mut self, ctx: &mut Ctx) -> Result<Flow, String> {
        if !self.checking {
            self.begin(ctx);
        }
        Ok(Flow::Stay)
    }

    fn title(&self) -> String {
        String::new()
    }

    fn id(&self, _: &Ctx) -> String {
        "dashboard".into()
    }

    fn focus(&self) -> Option<String> {
        Some(match self.list.selected()?.id.as_ref()? {
            Item::Start => "start".into(),
            Item::Setting(s) => s.name.clone(),
            Item::Language => "language".into(),
            Item::Action(a) => a.id.clone(),
            Item::Reset => "reset".into(),
        })
    }

    fn home(&self) -> bool {
        true
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        let rows = self.rows(ctx);
        self.list.set(rows);
        self.list.draw(area, buf, ctx);
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, Does)> {
        if self.list.typing() {
            return vec![
                ("↑↓", Does::Choose),
                ("⏎", Does::Open),
                ("esc", Does::CloseFilter),
            ];
        }
        vec![
            ("↑↓", Does::Choose),
            ("⏎", Does::Open),
            ("f", Does::Filter),
            ("q", Does::Quit),
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

    /// Rechecks requirements, since a card may have been plugged in. The first return runs the
    /// opening.
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

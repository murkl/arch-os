//! Question page: a list for a setting with options, else a text box, with the description above
//! and the error below. Shared by the opening, the dashboard, actions and runs.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use super::Then;
use crate::i18n::t;
use crate::spec::{self, Ask, Filter, Kind, Setting, Shell};
use crate::store::label;
use crate::ui::draw::{paragraph, put, wrap};
use crate::ui::input::Input;
use crate::ui::list::{List, Picked, Row};
use crate::ui::{Ctx, Data, Does, Flow, Key, Page, Tone};

/// A setting, or a task's question mid-run.
#[derive(Clone, Copy)]
pub enum Which {
    Setting(&'static Setting),
    Ask(&'static Ask),
}

impl Which {
    fn name(&self) -> &'static str {
        match self {
            Which::Setting(s) => &s.name,
            Which::Ask(a) => &a.name,
        }
    }

    fn title(&self) -> &'static str {
        match self {
            Which::Setting(s) => &s.title,
            Which::Ask(a) => &a.title,
        }
    }

    fn description(&self) -> &'static str {
        match self {
            Which::Setting(s) => &s.description,
            Which::Ask(a) => &a.description,
        }
    }

    fn kind(&self) -> Kind {
        match self {
            Which::Setting(s) => s.kind,
            Which::Ask(_) => Kind::List,
        }
    }

    fn filter(&self) -> Filter {
        match self {
            Which::Setting(s) => s.filter(),
            Which::Ask(a) => a.filter,
        }
    }

    fn options(
        &self,
    ) -> (
        &'static [String],
        Option<&'static Shell>,
        Option<&'static Shell>,
    ) {
        match self {
            Which::Setting(s) => (&s.options, s.options_from.as_ref(), s.prefill.as_ref()),
            Which::Ask(a) => (&a.options, a.options_from.as_ref(), None),
        }
    }
}

/// Options and a suggestion, read off the drawing thread, since a command's list can take a
/// moment.
pub struct Answers {
    pub options: Vec<(String, String)>,
    pub prefill: String,
    /// Why the options could not be read, which an empty list does not tell.
    pub failed: Option<String>,
}

/// Reader for the page's background job and for a run before it asks.
pub fn answers(which: Which, ctx: &Ctx) -> impl FnOnce() -> Answers + Send + 'static {
    let (options, from, prefill) = which.options();
    let env = ctx.env();
    let kind = which.kind();
    let name = which.name();
    move || {
        let mut failed = None;
        let options = match (kind, from) {
            (Kind::Bool, _) => vec![
                (spec::TRUE.into(), label(spec::TRUE)),
                (spec::FALSE.into(), label(spec::FALSE)),
            ],
            (_, Some(shell)) => match crate::script::lines(shell, &env) {
                Ok(lines) => lines
                    .into_iter()
                    .map(|l| match l.split_once('\t') {
                        Some((v, label)) => (v.trim().to_string(), label.trim().to_string()),
                        None => (l.trim().to_string(), label(l.trim())),
                    })
                    .collect(),
                Err(e) => {
                    crate::warn!("options for {name}: {e}");
                    failed = Some(e);
                    Vec::new()
                }
            },
            _ => options.iter().map(|o| (o.clone(), label(o))).collect(),
        };
        let prefill = match prefill {
            Some(shell) => crate::script::run(shell, &env).unwrap_or_else(|e| {
                crate::warn!("prefill for {name}: {e}");
                String::new()
            }),
            None => String::new(),
        };
        Answers {
            options,
            prefill,
            failed,
        }
    }
}

/// An option, or the row that opens the text box.
#[derive(Clone, Debug, PartialEq)]
enum Choice {
    Value(String),
    Own,
}

pub struct QuestionPage {
    which: Which,
    then: Then,
    loaded: Option<Answers>,
    list: Option<List<Choice>>,
    input: Option<Input>,
    problem: Option<String>,
    started: bool,
}

impl QuestionPage {
    pub fn setting(s: &'static Setting, then: Then) -> QuestionPage {
        QuestionPage::new(Which::Setting(s), then)
    }

    fn new(which: Which, then: Then) -> QuestionPage {
        QuestionPage {
            which,
            then,
            loaded: None,
            list: None,
            input: None,
            problem: None,
            started: false,
        }
    }

    /// A run's question, with its answers already read.
    pub fn ask(a: &'static Ask, answers: Answers) -> QuestionPage {
        let mut page = QuestionPage::new(Which::Ask(a), Then::Pop);
        page.started = true;
        page.loaded = Some(answers);
        page
    }

    /// Once answers are read: a list on the current answer or the suggestion, or a text box holding
    /// it.
    fn arrange(&mut self, ctx: &mut Ctx) {
        let Some(answers) = &self.loaded else { return };
        let mut current = ctx.store.get(self.which.name()).to_string();
        if let Which::Setting(s) = self.which {
            if answers.options.iter().any(|(v, _)| *v == current) {
                ctx.store.reoffer(&s.name);
            }
            // An invalid answer is why the question is asked again, so the error shows at once. A
            // list then opens on its suggestion, a box keeps its text. Options that could not be
            // read say why, instead of leaving a box that looks intended.
            let turned = (!current.is_empty())
                .then(|| ctx.store.invalid(s, &current))
                .flatten();
            if let Some(why) = turned.as_ref().or(answers.failed.as_ref()) {
                self.problem = Some(why.clone());
            }
            if current.is_empty() || (turned.is_some() && !answers.options.is_empty()) {
                current = answers.prefill.clone();
            }
        }
        if answers.options.is_empty() {
            let mut input = Input::new(&t(self.which.title()));
            input.text = current;
            self.input = Some(input);
            return;
        }
        let mut rows: Vec<Row<Choice>> = answers
            .options
            .iter()
            .map(|(v, l)| Row::new(Choice::Value(v.clone()), l.clone()))
            .collect();
        if self.which.kind() == Kind::OpenList {
            rows.push(Row::new(Choice::Own, format!("+ {}", t("Custom entry"))));
        }
        let mut list = List::filterable(rows);
        list.focus(&Choice::Value(current));
        if self.which.filter() == Filter::Open {
            list.open_filter();
        }
        self.list = Some(list);
    }

    fn commit(&mut self, value: String, ctx: &mut Ctx) -> Flow {
        if let Which::Setting(s) = self.which
            && let Some(why) = ctx.store.invalid(s, &value)
        {
            self.problem = Some(why);
            return Flow::Stay;
        }
        ctx.store.set(self.which.name(), &value);
        crate::info!("{}: {value}", self.which.name());
        if let Which::Setting(s) = self.which {
            // Applied before the next page, as the console keymap must hold for the next key.
            let _ = ctx.apply(s);
            ctx.save();
            ctx.resolve();
        }
        super::after(&self.then, ctx)
    }
}

impl Page for QuestionPage {
    /// A setting is only asked without a valid answer in the file. A task's question takes its
    /// answer from the environment, else stays unanswered.
    fn unattended(&mut self, ctx: &mut Ctx) -> Result<Flow, String> {
        let Some(answers) = &self.loaded else {
            return Ok(Flow::Stay);
        };
        match self.which {
            Which::Setting(s) => Err(match &self.problem {
                Some(why) => format!("{}: {why}", s.name),
                None => crate::i18n::tf("{{name}} is not answered.", &[("name", &s.name)]),
            }),
            Which::Ask(a) => {
                let value = std::env::var(&a.name).unwrap_or_default();
                if value.is_empty() {
                    crate::info!("{}: not set, so the task is skipped", a.name);
                    ctx.store.set(&a.name, "");
                    return Ok(Flow::Pop);
                }
                if !answers.options.iter().any(|(v, _)| *v == value) {
                    return Err(crate::i18n::tf(
                        "{{name}} is not one of the options.",
                        &[("name", &a.name)],
                    ));
                }
                Ok(self.commit(value, ctx))
            }
        }
    }

    fn title(&self) -> String {
        t(self.which.title())
    }

    fn id(&self, _: &Ctx) -> String {
        format!("question {}", self.which.name())
    }

    fn focus(&self) -> Option<String> {
        Some(match self.list.as_ref()?.selected()?.id.as_ref()? {
            Choice::Value(v) => v.clone(),
            Choice::Own => "own".into(),
        })
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        if !self.started {
            self.started = true;
            ctx.spawn(answers(self.which, ctx));
        }
        if self.loaded.is_some() && self.list.is_none() && self.input.is_none() {
            self.arrange(ctx);
        }
        let s = ctx.style;
        let mut y = area.y;
        let description = t(self.which.description());
        if !description.is_empty() {
            y = paragraph(buf, area, y, &description, s.tone(Tone::Muted)) + 1;
        }
        let problem_rows = self
            .problem
            .as_ref()
            .map_or(0, |p| wrap(p, usize::from(area.width)).len().max(2) as u16);
        let room = Rect::new(
            area.x,
            y,
            area.width,
            area.bottom().saturating_sub(y + problem_rows),
        );
        if let Some(input) = &self.input {
            input.draw(buf, room.x, room.y, room.width, ctx);
        } else if let Some(list) = &mut self.list {
            list.draw(room, buf, ctx);
        } else {
            put(buf, room.x, room.y, s.spinner(), 2, s.tone(Tone::Accent));
        }
        if let Some(problem) = &self.problem {
            paragraph(
                buf,
                area,
                area.bottom().saturating_sub(problem_rows),
                problem,
                s.tone(Tone::Error),
            );
        }
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, Does)> {
        // Esc leaves the question, which during a run opens the way out that stops it.
        let leave = if self.holds() { Does::Stop } else { Does::Back };
        if self.input.is_some() {
            let esc = if self.list.is_some() {
                Does::Return
            } else {
                leave
            };
            return vec![("⏎", Does::Use), ("esc", esc)];
        }
        let typing = self.list.as_ref().is_some_and(|l| l.typing());
        let mut h = vec![("↑↓", Does::Choose), ("⏎", Does::Use)];
        if typing {
            h.push((
                "esc",
                if self.which.filter() == Filter::Open {
                    leave
                } else {
                    Does::CloseFilter
                },
            ));
        } else {
            h.push(("f", Does::Filter));
            h.push(("esc", leave));
        }
        h
    }

    fn key(&mut self, key: Key, ctx: &mut Ctx) -> Flow {
        if let Some(input) = self.input.as_mut() {
            match key {
                Key::Enter => {
                    let value = input.text.trim().to_string();
                    return self.commit(value, ctx);
                }
                // Esc in a box opened from a list returns to the list instead of leaving the page.
                Key::Esc if self.list.is_some() => {
                    self.input = None;
                    self.problem = None;
                    return Flow::Stay;
                }
                Key::Esc => return Flow::Ignored,
                k => {
                    if input.key(k) {
                        self.problem = None;
                    }
                    return Flow::Stay;
                }
            }
        }
        let Some(list) = self.list.as_mut() else {
            return match key {
                Key::Esc | Key::Ctrl('c') => Flow::Ignored,
                _ => Flow::Stay,
            };
        };
        // A filter box open from the start has nothing to close, so esc leaves the question.
        if key == Key::Esc && list.typing() && self.which.filter() == Filter::Open {
            return Flow::Ignored;
        }
        match list.key(key) {
            Picked::Open(Choice::Own) => {
                self.problem = None;
                self.input = Some(Input::new(&t(self.which.title())));
                Flow::Stay
            }
            Picked::Open(Choice::Value(value)) => self.commit(value, ctx),
            Picked::Used => Flow::Stay,
            Picked::Ignored => Flow::Ignored,
        }
    }

    fn data(&mut self, data: Data, _: &mut Ctx) -> Flow {
        if let Data::Answers(answers) = data {
            self.loaded = Some(answers);
        }
        Flow::Stay
    }

    fn typing(&self) -> bool {
        self.input.is_some() || self.list.as_ref().is_some_and(|l| l.typing())
    }

    fn animating(&self, _: &Ctx) -> bool {
        self.loaded.is_none()
    }

    fn holds(&self) -> bool {
        matches!(self.which, Which::Ask(_))
    }

    fn note(&self, ctx: &Ctx) -> Option<String> {
        match self.then {
            Then::Opening => super::counter(ctx),
            _ => None,
        }
    }

    fn root(&self) -> bool {
        matches!(self.then, Then::Opening | Then::Start)
    }
}

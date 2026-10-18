//! The work: every task with a mark, filling in from the top, never a line of what they print,
//! which goes to the log. A task that asks first or has something to report interrupts the list.
//! The page ends on what the run came to and what may follow.

use std::time::{Duration, Instant};

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use super::confirm::YesNoPage;
use super::question::{self, QuestionPage};
use super::report::{Close, ReportPage};
use crate::i18n::{t, tf};
use crate::script::{self, Event, Failure, Session};
use crate::spec::Task;
use crate::ui::detail::{Act, Block, Detail, mark, words};
use crate::ui::draw::{cut, cut_front, put};
use crate::ui::list::Lead;
use crate::ui::{Ctx, Data, Flow, Key, Page, Tone};

#[derive(Clone, Copy, PartialEq)]
enum Mark {
    Pending,
    Ran,
    Skipped,
    Broken,
}

/// How far the task at the cursor has got through what it declared: a value to ask for, the
/// offer, the work, the check that the work took, what it has to report.
#[derive(Clone, Copy, PartialEq)]
enum Phase {
    Ask,
    Confirm,
    Run,
    Check,
    Report,
}

/// What this page pushed, and so what its being on top again means.
#[derive(Clone, Copy, PartialEq)]
enum Pushed {
    None,
    Ask,
    Confirm,
    Report,
}

/// How a run ended: in the module's words, or where it broke.
enum End {
    Known(String),
    Broke(Failure),
}

/// The pause before a result takes keys: what was typed while waiting must not dismiss it.
const SETTLE: Duration = Duration::from_millis(618);
/// How long a simulated task is shown running: long enough for the row to be read as it passes.
const SIMULATED: Duration = if cfg!(test) {
    Duration::ZERO
} else {
    Duration::from_secs(1)
};

pub struct RunPage {
    steps: Vec<&'static Task>,
    marks: Vec<Mark>,
    at: usize,
    phase: Phase,
    pushed: Pushed,
    session: Option<Session>,
    /// The line the running task drew last, where it declared its output its progress.
    latest: Option<String>,
    /// Each task that declared a test and got as far as running it, with its failure.
    tests: Vec<(&'static Task, Option<Failure>)>,
    /// Each task the result stands without, with its failure.
    optional: Vec<(&'static Task, Option<Failure>)>,
    started: Instant,
    /// How it ended, when, and how long it took.
    end: Option<(Result<(), End>, Instant, Duration)>,
    /// A simulated task ends when this passes.
    simulated: Option<Instant>,
    result: Detail,
    /// The answers were written out and the first step is due.
    began: bool,
    kick: bool,
    /// How many rows the module offers under a finished run and under a failed one, so the
    /// cursor opens on the row that goes on.
    rows_cache: (usize, usize),
}

impl RunPage {
    pub fn new(ctx: &Ctx) -> RunPage {
        let steps: Vec<&'static Task> = ctx
            .module
            .tasks
            .iter()
            .filter(|t| t.applies(ctx.store.getter()))
            .collect();
        crate::info!("run: {} tasks", steps.len());
        RunPage {
            marks: vec![Mark::Pending; steps.len()],
            steps,
            at: 0,
            phase: Phase::Ask,
            pushed: Pushed::None,
            session: None,
            latest: None,
            tests: Vec::new(),
            optional: Vec::new(),
            started: Instant::now(),
            end: None,
            simulated: None,
            result: Detail::default(),
            began: false,
            kick: false,
            rows_cache: (0, 0),
        }
    }

    fn task(&self) -> &'static Task {
        self.steps[self.at]
    }

    /// Takes on the task at the cursor, phase by phase, until something runs or asks.
    fn step(&mut self, ctx: &mut Ctx) -> Flow {
        loop {
            if self.at >= self.steps.len() {
                return self.finish(Ok(()), ctx);
            }
            let task = self.task();
            match self.phase {
                Phase::Ask => {
                    self.phase = Phase::Confirm;
                    if let Some(ask) = &task.asks {
                        ctx.spawn(question::answers(question::Which::Ask(ask), ctx));
                        return Flow::Stay;
                    }
                }
                Phase::Confirm => {
                    self.phase = Phase::Run;
                    if let Some(confirm) = &task.confirm {
                        self.pushed = Pushed::Confirm;
                        // No, like every confirm. Yes after a task this one follows from has run.
                        let yes = self.follows(task);
                        return Flow::Push(Box::new(YesNoPage::ask(
                            t(&task.title),
                            &ctx.expand(&t(confirm)),
                            yes,
                        )));
                    }
                }
                Phase::Run => return self.start(ctx),
                Phase::Check => {
                    self.phase = Phase::Report;
                    if task.test && !ctx.store.dry_run() {
                        crate::info!("{}: test", task.title);
                        let step = ctx.step(&t(&task.title), false, task.test_script());
                        match script::start(step, &ctx.env(), ctx.run_sink()) {
                            Ok(session) => {
                                self.session = Some(session);
                                return Flow::Stay;
                            }
                            Err(e) => {
                                let f = Failure::new(
                                    &ctx.step(&t(&task.title), false, task.test_script()),
                                    e,
                                );
                                self.tests.push((task, Some(f)));
                            }
                        }
                    }
                }
                Phase::Report => {
                    if let Some(report) = &task.report {
                        self.pushed = Pushed::Report;
                        ctx.save();
                        let note = self.tally();
                        return Flow::Push(Box::new(
                            ReportPage::new(
                                t(&task.title),
                                ctx.expand(&t(report)),
                                None,
                                false,
                                Close::PopN(1),
                            )
                            .noted(note),
                        ));
                    }
                    self.advance();
                }
            }
        }
    }

    /// Whether a task this one names under yes-after ran earlier in this run.
    fn follows(&self, task: &Task) -> bool {
        self.steps[..self.at]
            .iter()
            .zip(&self.marks)
            .any(|(t, m)| *m == Mark::Ran && task.yes_after.contains(&t.id))
    }

    fn advance(&mut self) {
        self.at += 1;
        self.phase = Phase::Ask;
        self.latest = None;
    }

    /// Runs the task at the cursor in the background, or only shows it for a moment on a dry run.
    fn start(&mut self, ctx: &mut Ctx) -> Flow {
        let task = self.task();
        if ctx.store.dry_run() && !task.simulates {
            crate::info!("{}: simulated", task.title);
            self.simulated = Some(Instant::now() + SIMULATED);
            return Flow::Stay;
        }
        crate::info!("{}", task.title);
        let step = ctx.step(&t(&task.title), false, task.script());
        match script::start(step, &ctx.env(), ctx.run_sink()) {
            Ok(session) => {
                self.session = Some(session);
                Flow::Stay
            }
            Err(e) => {
                let f = Failure::new(&ctx.step(&t(&task.title), false, task.script()), e);
                self.fell(f, ctx)
            }
        }
    }

    /// What becomes of a task whose work failed: one the result stands without is noted and
    /// passed, without test or report; any other ends the run.
    fn fell(&mut self, f: Failure, ctx: &mut Ctx) -> Flow {
        let task = self.task();
        if !task.allow_failure {
            let end = match crate::ui::told(ctx.module, &task.errors, &f) {
                Some(words) => End::Known(ctx.expand(&words)),
                None => End::Broke(f),
            };
            return self.finish(Err(end), ctx);
        }
        crate::warn!("{}: {f}", task.title);
        self.marks[self.at] = Mark::Broken;
        self.optional.push((task, Some(f)));
        self.advance();
        self.step(ctx)
    }

    fn finish(&mut self, result: Result<(), End>, ctx: &mut Ctx) -> Flow {
        let took = self.started.elapsed();
        match &result {
            Ok(()) => crate::info!("run: ok"),
            Err(End::Known(words)) => {
                crate::error!("run: failed: {}", words.lines().next().unwrap_or_default())
            }
            Err(End::Broke(f)) => crate::error!("run: failed: {f}"),
        }
        self.end = Some((result, Instant::now(), took));
        self.session = None;
        self.simulated = None;
        // Whatever a run was given is gone the moment it is over, whether it worked or not.
        ctx.store.forget();
        Flow::Stay
    }

    fn settled(&self) -> bool {
        self.end
            .as_ref()
            .is_some_and(|(_, at, _)| at.elapsed() >= SETTLE)
    }

    /// What the run has come to beyond its list: the optional tasks that failed and the tests
    /// that ran, and whether it is worth a look.
    fn tally(&self) -> Option<(String, Tone)> {
        let mut said = Vec::new();
        let mut alarm = false;
        let failed = |v: &[(&Task, Option<Failure>)]| v.iter().filter(|(_, f)| f.is_some()).count();
        if failed(&self.optional) > 0 {
            said.push(tf(
                "{{n}} of {{of}} optional tasks failed",
                &[("n", &failed(&self.optional)), ("of", &self.optional.len())],
            ));
            alarm = true;
        }
        if !self.tests.is_empty() {
            let ok = self.tests.len() - failed(&self.tests);
            said.push(tf(
                "{{n}} of {{of}} tests passed",
                &[("n", &ok), ("of", &self.tests.len())],
            ));
            alarm = alarm || ok < self.tests.len();
        }
        (!said.is_empty()).then(|| {
            (
                said.join(" · "),
                if alarm { Tone::Warn } else { Tone::Muted },
            )
        })
    }

    /// Everything the run went on past, in the order it is read.
    fn failures(&self) -> Vec<(String, Failure)> {
        self.optional
            .iter()
            .chain(&self.tests)
            .filter_map(|(task, f)| f.clone().map(|f| (t(&task.title), f)))
            .collect()
    }

    fn clock(d: Duration) -> String {
        let secs = d.as_secs();
        if secs >= 3600 {
            format!("{}:{:02}:{:02}", secs / 3600, secs / 60 % 60, secs % 60)
        } else {
            format!("{:02}:{:02}", secs / 60, secs % 60)
        }
    }

    /// The outcome and what may come next: each a choice, none a must.
    fn draw_end(&mut self, area: Rect, buf: &mut Buffer, ctx: &Ctx) {
        let Some((result, _, took)) = &self.end else {
            return;
        };
        let (body, acts): (Vec<Block>, Vec<Act>) = match result {
            Ok(()) => {
                let mut body = vec![
                    mark(false),
                    Block::Blank,
                    Block::Heading(tf(
                        "Finished in {{time}}",
                        &[("time", &RunPage::clock(*took))],
                    )),
                ];
                if let Some((note, tone)) = self.tally() {
                    body.push(Block::Text(note, tone));
                }
                let mut acts = Vec::new();
                let failures = self.failures();
                if !failures.is_empty() {
                    let verdict = self.tally().map(|(n, _)| n).unwrap_or_default();
                    acts.push(Act::new(t("Test results"), move |_| {
                        Flow::Push(Box::new(super::results::ResultsPage::new(
                            verdict.clone(),
                            failures.clone(),
                        )))
                    }));
                }
                for action in ctx.rows(&ctx.module.on.success) {
                    acts.push(
                        Act::new(t(&action.title), move |ctx: &mut Ctx| {
                            super::action::open(ctx, action, false)
                        })
                        .describe(t(&action.description)),
                    );
                }
                acts.push(Act::new(t("Continue"), |ctx: &mut Ctx| {
                    if ctx.leaves() {
                        Flow::Push(Box::new(super::leave::LeavePage::new(ctx, false, false)))
                    } else {
                        Flow::Quit
                    }
                }));
                (body, acts)
            }
            Err(End::Known(text)) => {
                let mut body = vec![mark(true), Block::Blank];
                body.extend(words(text));
                (body, vec![Act::new(t("Back"), |_| Flow::Home)])
            }
            Err(End::Broke(f)) => {
                let stopped = self
                    .steps
                    .get(self.at)
                    .map(|t_| t(&t_.title))
                    .unwrap_or_else(|| t(&ctx.module.title));
                let mut body = vec![
                    mark(true),
                    Block::Blank,
                    Block::Heading(t("Failed")),
                    Block::Text(
                        tf(
                            "It stopped at {{task}}, and nothing after that has run.",
                            &[("task", &stopped)],
                        ),
                        Tone::Normal,
                    ),
                    Block::Blank,
                ];
                body.extend(crate::ui::detail::failure(f));
                let mut acts = Vec::new();
                for action in ctx.rows(&ctx.module.on.failure) {
                    acts.push(
                        Act::new(t(&action.title), move |ctx: &mut Ctx| {
                            super::action::open(ctx, action, false)
                        })
                        .describe(t(&action.description)),
                    );
                }
                acts.push(Act::new(t("Back to the dashboard"), |_| {
                    Flow::Push(Box::new(YesNoPage::home()))
                }));
                (body, acts)
            }
        };
        let fresh = self.result.body.is_empty();
        self.result.set(body, acts);
        if fresh {
            // Opens on the row that goes on: an action is chosen on purpose, never by an enter
            // meant for the page before.
            let last = self.result_len().saturating_sub(1);
            self.result.focus(last);
        }
        self.result.draw(area, buf, ctx);
    }

    fn result_len(&self) -> usize {
        match &self.end {
            Some((Ok(()), ..)) => {
                1 + usize::from(!self.failures().is_empty()) + self.success_rows()
            }
            Some((Err(End::Known(_)), ..)) => 1,
            Some((Err(End::Broke(_)), ..)) => 1 + self.failure_rows(),
            None => 0,
        }
    }

    fn success_rows(&self) -> usize {
        self.rows_cache.0
    }

    fn failure_rows(&self) -> usize {
        self.rows_cache.1
    }

    /// The list of tasks with their marks, the window following the cursor. A progress line costs
    /// a row under its task and is cut at its start: a bar says how far it got at its end.
    fn draw_list(&self, area: Rect, buf: &mut Buffer, ctx: &Ctx) {
        let s = &ctx.style;
        let running = self.end.is_none() && self.at < self.steps.len();
        let progress = running && self.task().progress && self.phase == Phase::Run;
        let rows = usize::from(area.height) - usize::from(progress && self.latest.is_some());
        if rows == 0 {
            return;
        }
        let top = if self.at >= rows {
            (self.at + 1 - rows).min(self.steps.len().saturating_sub(rows))
        } else {
            0
        };
        let mut y = area.y;
        for (i, task) in self.steps.iter().enumerate().skip(top).take(rows) {
            let (lead, style) = match self.marks[i] {
                Mark::Ran => (Lead::Glyph(s.glyphs.ok, Tone::Accent), s.tone(Tone::Muted)),
                Mark::Skipped => (Lead::Glyph(s.glyphs.skip, Tone::Muted), s.tone(Tone::Muted)),
                Mark::Broken => (Lead::Glyph(s.glyphs.fail, Tone::Error), s.tone(Tone::Muted)),
                Mark::Pending if i == self.at && running => {
                    (Lead::Glyph(s.spinner(), Tone::Accent), s.bold(Tone::Normal))
                }
                Mark::Pending => (Lead::None, s.tone(Tone::Muted)),
            };
            if let Lead::Glyph(glyph, tone) = lead {
                put(buf, area.x, y, glyph, 1, s.tone(tone));
            }
            put(
                buf,
                area.x + 2,
                y,
                &cut(
                    &t(&task.title),
                    area.width.saturating_sub(2) as usize,
                    s.glyphs.ellipsis,
                ),
                area.width.saturating_sub(2),
                style,
            );
            y += 1;
            if i == self.at
                && progress
                && let Some(latest) = &self.latest
            {
                put(
                    buf,
                    area.x + 2,
                    y,
                    &cut_front(
                        latest,
                        area.width.saturating_sub(2) as usize,
                        s.glyphs.ellipsis,
                    ),
                    area.width.saturating_sub(2),
                    s.tone(Tone::Muted),
                );
                y += 1;
            }
        }
    }
}

impl Page for RunPage {
    fn title(&self) -> String {
        String::new()
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        if self.at == 0
            && self.phase == Phase::Ask
            && self.pushed == Pushed::None
            && self.session.is_none()
            && self.end.is_none()
            && self.simulated.is_none()
            && self.marks.iter().all(|m| *m == Mark::Pending)
            && !self.began
        {
            self.began = true;
            // The answers this run starts with are written out whole first: a task that copies
            // the file hands on exactly those.
            ctx.save();
            self.rows_cache = (
                ctx.rows(&ctx.module.on.success).len(),
                ctx.rows(&ctx.module.on.failure).len(),
            );
            self.kick = true;
        }
        if self.end.is_some() {
            self.draw_end(area, buf, ctx);
            return;
        }
        let s = ctx.style;
        let headline = tf(
            "Working · {{time}}",
            &[("time", &RunPage::clock(self.started.elapsed()))],
        );
        put(buf, area.x, area.y, s.spinner(), 1, s.tone(Tone::Accent));
        put(
            buf,
            area.x + 2,
            area.y,
            &headline,
            area.width.saturating_sub(2),
            s.bold(Tone::Normal),
        );
        let list = Rect::new(
            area.x,
            area.y + 2,
            area.width,
            area.height.saturating_sub(2),
        );
        self.draw_list(list, buf, ctx);
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, String)> {
        if self.end.is_some() {
            return if self.settled() {
                self.result.hints()
            } else {
                Vec::new()
            };
        }
        vec![("esc", t("leave"))]
    }

    fn key(&mut self, key: Key, ctx: &mut Ctx) -> Flow {
        if self.end.is_some() {
            if !self.settled() {
                return Flow::Stay;
            }
            return match self.result.key(key, ctx) {
                Flow::Ignored
                    if matches!(
                        key,
                        Key::Esc | Key::Backspace | Key::Char('q') | Key::Ctrl('c')
                    ) =>
                {
                    Flow::Ignored
                }
                Flow::Ignored => Flow::Stay,
                flow => flow,
            };
        }
        // Killing a half-finished package transaction is worse than waiting for it: nothing but
        // the way out means anything while a task runs.
        match key {
            Key::Esc | Key::Ctrl('c') | Key::Char('q') | Key::Backspace => Flow::Ignored,
            _ => Flow::Stay,
        }
    }

    fn run(&mut self, event: Event, ctx: &mut Ctx) -> Flow {
        match event {
            Event::Line(line) => {
                self.latest = Some(line);
                Flow::Stay
            }
            Event::Exit(result) => {
                self.session = None;
                let task = self.task();
                match self.phase {
                    Phase::Run => match result {
                        Ok(()) => {
                            self.marks[self.at] = Mark::Ran;
                            if task.allow_failure {
                                self.optional.push((task, None));
                            }
                            self.phase = Phase::Check;
                            self.step(ctx)
                        }
                        Err(f) => self.fell(f, ctx),
                    },
                    Phase::Report => {
                        // Not a failed run: the work said it worked, and something looking at the
                        // machine afterwards disagreed.
                        if let Err(f) = &result {
                            crate::warn!("{}: test: {f}", task.title);
                        }
                        self.tests.push((task, result.err()));
                        self.step(ctx)
                    }
                    _ => Flow::Stay,
                }
            }
        }
    }

    fn data(&mut self, data: Data, ctx: &mut Ctx) -> Flow {
        let Data::Answers(answers) = data else {
            return Flow::Stay;
        };
        let task = self.task();
        let Some(ask) = &task.asks else {
            return Flow::Stay;
        };
        // Nothing to choose from skips the task.
        if answers.options.is_empty() {
            crate::info!("{}: nothing to choose from", task.title);
            self.marks[self.at] = Mark::Skipped;
            self.advance();
            return self.step(ctx);
        }
        self.pushed = Pushed::Ask;
        Flow::Push(Box::new(QuestionPage::ask(ask, answers)))
    }

    fn tick(&mut self, ctx: &mut Ctx) -> Flow {
        if self.kick {
            self.kick = false;
            return self.step(ctx);
        }
        if let Some(until) = self.simulated
            && Instant::now() >= until
        {
            self.simulated = None;
            self.marks[self.at] = Mark::Ran;
            // Straight to what it has to report: there is nothing on the machine for its test.
            self.phase = Phase::Report;
            return self.step(ctx);
        }
        Flow::Stay
    }

    /// Back on top after what this page pushed: the answer to a question, a yes or no, a report
    /// read.
    fn resumed(&mut self, ctx: &mut Ctx) -> Flow {
        let pushed = std::mem::replace(&mut self.pushed, Pushed::None);
        match pushed {
            Pushed::None => Flow::Stay,
            Pushed::Ask => {
                let task = self.task();
                let name = task
                    .asks
                    .as_ref()
                    .map(|a| a.name.as_str())
                    .unwrap_or_default();
                crate::info!("{name}: {}", ctx.store.get(name));
                self.step(ctx)
            }
            Pushed::Confirm => {
                if ctx.answered.take() == Some(true) {
                    return self.start(ctx);
                }
                crate::info!("{}: declined", self.task().title);
                self.marks[self.at] = Mark::Skipped;
                self.advance();
                self.step(ctx)
            }
            Pushed::Report => {
                self.advance();
                self.step(ctx)
            }
        }
    }

    fn note(&self, _: &Ctx) -> Option<String> {
        if self.end.is_some() {
            return None;
        }
        Some(tf(
            "{{at}} of {{of}}",
            &[
                ("at", &(self.at + 1).min(self.steps.len())),
                ("of", &self.steps.len()),
            ],
        ))
    }

    fn root(&self) -> bool {
        true
    }

    fn holds(&self) -> bool {
        self.end.is_none()
    }

    fn stop(&mut self) {
        if let Some(session) = &self.session {
            crate::warn!("run: stopped");
            session.kill();
        }
    }

    fn animating(&self, _: &Ctx) -> bool {
        self.end.is_none() || !self.settled()
    }
}

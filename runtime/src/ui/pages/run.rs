//! Run page: every task with a mark, filled from the top, and its output on tab, also logged. A
//! task's question or report interrupts the list, and the page ends on the outcome and next rows.

use std::collections::VecDeque;
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
use crate::ui::draw::{cut, cut_front, put, wrap};
use crate::ui::list::Lead;
use crate::ui::{Ctx, Data, Does, Flow, Key, Page, Tone};

#[derive(Clone, Copy, PartialEq)]
enum Mark {
    Pending,
    Ran,
    Skipped,
    Broken,
}

/// Progress of the current task: question, confirmation, run, test, report.
#[derive(Clone, Copy, PartialEq)]
enum Phase {
    Ask,
    Confirm,
    Run,
    Check,
    Report,
}

/// Page this page pushed, which tells what resuming means.
#[derive(Clone, Copy, PartialEq)]
enum Pushed {
    None,
    Ask,
    Confirm,
    Report,
}

enum Out {
    Title(String),
    Line(String),
}

/// Failed run: the module's text, the failure, or stopped by the leave page.
enum End {
    Known(String),
    Broke(Failure),
    Stopped,
}

/// Pause before the outcome takes keys, so keys typed while waiting do not dismiss it.
const SETTLE: Duration = Duration::from_millis(618);
/// Display time of a simulated task, long enough to read its row.
const SIMULATED: Duration = if cfg!(test) {
    Duration::ZERO
} else {
    Duration::from_secs(1)
};
/// Lines the text view keeps: more than any console has rows, however they wrap.
const KEPT: usize = 1000;

/// The answers and the task's texts, translated.
fn task_env(task: &Task, ctx: &Ctx) -> Vec<(String, String)> {
    let mut env = ctx.env();
    env.extend(
        task.texts
            .iter()
            .map(|(name, text)| (name.clone(), t(text))),
    );
    env
}

pub struct RunPage {
    steps: Vec<&'static Task>,
    marks: Vec<Mark>,
    at: usize,
    phase: Phase,
    pushed: Pushed,
    session: Option<Session>,
    /// Last line of the running task, where it declares its output as progress.
    latest: Option<String>,
    /// Inhibits shutdown and sleep while the tasks run.
    hold: Option<script::Hold>,
    /// Run output under each task title, and the line being redrawn in place.
    transcript: VecDeque<Out>,
    drawing: Option<String>,
    /// Shows the text view instead of the list.
    text: bool,
    /// Tasks whose declared test ran, with its failure.
    tests: Vec<(&'static Task, Option<Failure>)>,
    /// Tasks allowed to fail, with their failure.
    optional: Vec<(&'static Task, Option<Failure>)>,
    started: Instant,
    /// Outcome with the module's report text on success, end time and duration.
    end: Option<(Result<Option<String>, End>, Instant, Duration)>,
    /// End time of a simulated task.
    simulated: Option<Instant>,
    result: Detail,
    /// Answers saved and the first step due.
    began: bool,
    kick: bool,
    /// Module rows after success and after failure, so the cursor opens on the row that goes on.
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
            hold: None,
            transcript: VecDeque::new(),
            drawing: None,
            text: false,
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

    /// Advances the current task phase by phase until something runs or asks.
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
                        // No like every confirm, yes once a `yes_after` task has run.
                        let yes = self.follows(task);
                        return Flow::Push(Box::new(YesNoPage::ask(
                            format!("confirm {}", task.id),
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
                        match script::start(step, &task_env(task, ctx), ctx.run_sink()) {
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
                                format!("report {}", task.id),
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

    /// A `yes_after` task ran earlier in this run.
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

    /// Runs the current task in the background, or only shows it briefly on a dry run.
    fn start(&mut self, ctx: &mut Ctx) -> Flow {
        let task = self.task();
        ctx.trace.line("task", &task.id);
        self.keep(Out::Title(t(&task.title)));
        if ctx.store.dry_run() && !task.simulates {
            crate::info!("{}: simulated", task.title);
            self.simulated = Some(Instant::now() + SIMULATED);
            return Flow::Stay;
        }
        crate::info!("{}", task.title);
        let step = ctx.step(&t(&task.title), false, task.script());
        match script::start(step, &task_env(task, ctx), ctx.run_sink()) {
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

    /// A task allowed to fail is noted and passed without test or report. Any other ends the run.
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
            Err(End::Stopped) => crate::warn!("run: stopped"),
        }
        // Expanded before the answers it may name are forgotten.
        let result = result.map(|()| ctx.module.report.as_ref().map(|r| ctx.expand(&t(r))));
        self.end = Some((result, Instant::now(), took));
        self.session = None;
        self.simulated = None;
        self.hold = None;
        // Typed inputs are forgotten right after the run, success or not.
        ctx.store.forget();
        Flow::Stay
    }

    fn keep(&mut self, out: Out) {
        if self.transcript.len() == KEPT {
            self.transcript.pop_front();
        }
        self.transcript.push_back(out);
    }

    /// Newest lines that fit, the redrawn line last, long lines wrapped.
    fn draw_text(&self, area: Rect, buf: &mut Buffer, ctx: &Ctx) {
        let s = &ctx.style;
        let width = usize::from(area.width);
        let height = usize::from(area.height);
        let drawing = self
            .drawing
            .iter()
            .map(|l| (l, s.tone(Tone::Normal), false));
        let lines = self
            .transcript
            .iter()
            .enumerate()
            .map(|(i, out)| match out {
                Out::Title(title) => (title, s.bold(Tone::Accent), i > 0),
                Out::Line(line) => (line, s.tone(Tone::Normal), false),
            })
            .chain(drawing);
        let mut rows = Vec::new();
        for (text, style, gap) in lines.rev() {
            rows.extend(wrap(text, width).into_iter().rev().map(|r| (r, style)));
            if gap {
                rows.push((String::new(), style));
            }
            if rows.len() >= height {
                break;
            }
        }
        rows.truncate(height);
        for (y, (row, style)) in (area.y..).zip(rows.iter().rev()) {
            put(buf, area.x, y, row, area.width, *style);
        }
    }

    fn settled(&self) -> bool {
        self.end
            .as_ref()
            .is_some_and(|(_, at, _)| at.elapsed() >= SETTLE)
    }

    fn way(&self) -> Option<Way> {
        match &self.end {
            Some((Ok(_), ..)) => Some(Way::Leave),
            Some((Err(End::Broke(_)), ..)) => Some(Way::Ask),
            Some((Err(_), ..)) => Some(Way::Back),
            None => None,
        }
    }

    /// Failed optional tasks and passed tests, in the warning tone when either falls short.
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

    /// Failures the run went past, optional tasks first, then tests.
    fn failures(&self) -> Vec<(String, Failure)> {
        self.optional
            .iter()
            .chain(&self.tests)
            .filter_map(|(task, f)| f.clone().map(|f| (t(&task.title), f)))
            .collect()
    }

    fn stopped_at(&self, ctx: &Ctx) -> String {
        let task = self
            .steps
            .get(self.at)
            .map(|t_| t(&t_.title))
            .unwrap_or_else(|| t(&ctx.module.title));
        tf("Stopped at {{task}}", &[("task", &task)])
    }

    fn clock(d: Duration) -> String {
        let secs = d.as_secs();
        if secs >= 3600 {
            format!("{}:{:02}:{:02}", secs / 3600, secs / 60 % 60, secs % 60)
        } else {
            format!("{:02}:{:02}", secs / 60, secs % 60)
        }
    }

    /// Outcome and next rows, each optional.
    fn draw_end(&mut self, area: Rect, buf: &mut Buffer, ctx: &Ctx) {
        let Some((result, _, took)) = &self.end else {
            return;
        };
        let (body, acts): (Vec<Block>, Vec<Act>) = match result {
            Ok(report) => {
                let mut body = vec![mark(false), Block::Blank];
                if let Some(report) = report {
                    body.extend(words(report));
                    body.push(Block::Blank);
                }
                body.push(Block::Text(
                    tf("Took {{time}}", &[("time", &RunPage::clock(*took))]),
                    Tone::Muted,
                ));
                if let Some((note, tone)) = self.tally() {
                    body.push(Block::Text(note, tone));
                }
                let mut acts = Vec::new();
                let failures = self.failures();
                if !failures.is_empty() {
                    let verdict = self.tally().map(|(n, _)| n).unwrap_or_default();
                    acts.push(
                        Act::new(t("Test results"), move |_| {
                            Flow::Push(Box::new(super::results::ResultsPage::new(
                                verdict.clone(),
                                failures.clone(),
                            )))
                        })
                        .does(Does::Open),
                    );
                }
                for action in ctx.rows(&ctx.module.on.success) {
                    acts.push(
                        Act::new(t(&action.title), move |ctx: &mut Ctx| {
                            super::action::open(ctx, action, false)
                        })
                        .describe(t(&action.description)),
                    );
                }
                acts.push(
                    Act::new(t("Continue"), |ctx: &mut Ctx| onward(Way::Leave, ctx))
                        .does(Does::Continue),
                );
                (body, acts)
            }
            Err(End::Known(text)) => {
                let mut body = vec![mark(true), Block::Blank];
                body.extend(words(text));
                (
                    body,
                    vec![Act::new(t("Back"), |ctx| onward(Way::Back, ctx)).does(Does::Back)],
                )
            }
            Err(End::Stopped) => (
                vec![
                    mark(true),
                    Block::Blank,
                    Block::Heading(self.stopped_at(ctx)),
                    Block::Text(t("Nothing after it ran."), Tone::Normal),
                ],
                vec![Act::new(t("Back"), |ctx| onward(Way::Back, ctx)).does(Does::Back)],
            ),
            Err(End::Broke(f)) => {
                let mut body = vec![
                    mark(true),
                    Block::Blank,
                    Block::Heading(self.stopped_at(ctx)),
                    Block::Text(t("Nothing after it ran."), Tone::Normal),
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
                acts.push(
                    Act::new(t("Back to the dashboard"), |ctx| onward(Way::Ask, ctx))
                        .does(Does::Back),
                );
                (body, acts)
            }
        };
        let fresh = self.result.body.is_empty();
        self.result.set(body, acts);
        if fresh {
            // Opens on the last row, so no action is chosen by an enter meant for the page before.
            let last = self.result_len().saturating_sub(1);
            self.result.focus(last);
        }
        self.result.draw(area, buf, ctx);
    }

    fn result_len(&self) -> usize {
        match &self.end {
            Some((Ok(_), ..)) => 1 + usize::from(!self.failures().is_empty()) + self.success_rows(),
            Some((Err(End::Known(_) | End::Stopped), ..)) => 1,
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

    /// Tasks with their marks, scrolled to the cursor. A progress line takes a row under its task
    /// and is cut at the front, since a bar shows its progress at the end.
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

/// Where back leads after the run, as the last row does.
#[derive(Clone, Copy)]
enum Way {
    /// Success: the leave page, or quit.
    Leave,
    /// Stopped run: the dashboard.
    Back,
    /// Failed run: the dashboard after a question, since the failure shows only on this page.
    Ask,
}

fn onward(way: Way, ctx: &mut Ctx) -> Flow {
    match way {
        Way::Leave if ctx.leaves() => {
            Flow::Push(Box::new(super::leave::LeavePage::new(ctx, false)))
        }
        Way::Leave => Flow::Quit,
        Way::Back => Flow::Home,
        Way::Ask => Flow::Push(Box::new(YesNoPage::home())),
    }
}

impl Page for RunPage {
    /// The run goes on by itself.
    fn unattended(&mut self, _: &mut Ctx) -> Result<Flow, String> {
        Ok(Flow::Stay)
    }

    fn finished(&self, ctx: &Ctx) -> Option<Result<String, String>> {
        if !self.settled() {
            return None;
        }
        let (result, _, took) = self.end.as_ref()?;
        let tally = self.tally().map(|(note, _)| note);
        Some(match result {
            Ok(report) => {
                let mut lines = report.iter().cloned().collect::<Vec<_>>();
                lines.push(tf("Took {{time}}", &[("time", &RunPage::clock(*took))]));
                lines.extend(tally);
                Ok(lines.join("\n"))
            }
            Err(End::Known(text)) => Err(text.clone()),
            Err(End::Stopped) => Err(format!(
                "{}\n{}",
                self.stopped_at(ctx),
                t("Nothing after it ran.")
            )),
            Err(End::Broke(f)) => Err(format!(
                "{}\n{}\n{f}",
                self.stopped_at(ctx),
                t("Nothing after it ran.")
            )),
        })
    }

    /// Empty while running or stopped by the leave page, which then titles it. Otherwise the
    /// outcome, for the header.
    fn id(&self, _: &Ctx) -> String {
        match &self.end {
            None => "run",
            Some((Ok(_), ..)) => "run done",
            Some((Err(End::Stopped), ..)) => "run stopped",
            Some((Err(_), ..)) => "run failed",
        }
        .into()
    }

    fn title(&self) -> String {
        match &self.end {
            None | Some((Err(End::Stopped), ..)) => String::new(),
            Some((Ok(_), ..)) => t("Done"),
            Some((Err(_), ..)) => t("Failed"),
        }
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
            // Saves all answers first, so a task copying the file hands on exactly these.
            ctx.save();
            // Tests inhibit nothing on the machine they run on.
            if !ctx.store.dry_run() && !cfg!(test) {
                self.hold = script::hold(&ctx.product_title(), &t(&ctx.module.title));
            }
            self.rows_cache = (
                ctx.rows(&ctx.module.on.success).len(),
                ctx.rows(&ctx.module.on.failure).len(),
            );
            self.kick = true;
        }
        if self.end.is_some() && !self.text {
            self.draw_end(area, buf, ctx);
            return;
        }
        let s = ctx.style;
        let (glyph, tone, headline) = match &self.end {
            None => (
                s.spinner(),
                Tone::Accent,
                tf(
                    "Running · {{time}}",
                    &[("time", &RunPage::clock(self.started.elapsed()))],
                ),
            ),
            Some((Ok(_), _, took)) => (
                s.glyphs.ok,
                Tone::Accent,
                tf("Took {{time}}", &[("time", &RunPage::clock(*took))]),
            ),
            Some((Err(_), ..)) => (s.glyphs.fail, Tone::Error, self.stopped_at(ctx)),
        };
        put(buf, area.x, area.y, glyph, 1, s.tone(tone));
        put(
            buf,
            area.x + 2,
            area.y,
            &headline,
            area.width.saturating_sub(2),
            s.bold(Tone::Normal),
        );
        let below = Rect::new(
            area.x,
            area.y + 2,
            area.width,
            area.height.saturating_sub(2),
        );
        if self.text {
            self.draw_text(below, buf, ctx);
        } else {
            self.draw_list(below, buf, ctx);
        }
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, Does)> {
        let view = (
            "tab",
            if self.text {
                Does::Compact
            } else {
                Does::Details
            },
        );
        if self.end.is_none() {
            return vec![view, ("esc", Does::Stop)];
        }
        if !self.settled() {
            return Vec::new();
        }
        let mut hints = if self.text {
            Vec::new()
        } else {
            self.result.hints()
        };
        hints.push(view);
        hints
    }

    fn key(&mut self, key: Key, ctx: &mut Ctx) -> Flow {
        let way_out = matches!(
            key,
            Key::Esc | Key::Backspace | Key::Char('q') | Key::Ctrl('c')
        );
        if key == Key::Tab {
            self.text = !self.text;
            return Flow::Stay;
        }
        if self.end.is_some() && !self.settled() {
            return Flow::Stay;
        }
        // Killing a half-finished package transaction is worse than waiting, so only leaving works
        // while a task runs.
        if self.end.is_none() {
            return if way_out { Flow::Ignored } else { Flow::Stay };
        }
        // Back acts as the last row, never returning to the questions still behind the run.
        if matches!(key, Key::Esc | Key::Backspace)
            && let Some(way) = self.way()
        {
            return onward(way, ctx);
        }
        // The text view hides the rows a key would choose.
        if self.text {
            return if way_out { Flow::Ignored } else { Flow::Stay };
        }
        match self.result.key(key, ctx) {
            Flow::Ignored if way_out => Flow::Ignored,
            Flow::Ignored => Flow::Stay,
            flow => flow,
        }
    }

    fn run(&mut self, event: Event, ctx: &mut Ctx) -> Flow {
        if self.end.is_some() {
            return Flow::Stay;
        }
        match event {
            Event::Line(line) => {
                self.latest = Some(line.clone());
                self.drawing = None;
                self.keep(Out::Line(line));
                Flow::Stay
            }
            Event::Drawn(line) => {
                self.latest = Some(line.clone());
                self.drawing = Some(line);
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
                        // A failed test does not fail the run. The task succeeded, a later check
                        // disagreed.
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
        if self.end.is_some() {
            return Flow::Stay;
        }
        let task = self.task();
        let Some(ask) = &task.asks else {
            return Flow::Stay;
        };
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
        if self.end.is_some() {
            return Flow::Stay;
        }
        if self.kick {
            self.kick = false;
            return self.step(ctx);
        }
        if let Some(until) = self.simulated
            && Instant::now() >= until
        {
            self.simulated = None;
            self.marks[self.at] = Mark::Ran;
            // Skips the test, since a simulated task changed nothing on the machine.
            self.phase = Phase::Report;
            return self.step(ctx);
        }
        Flow::Stay
    }

    fn resumed(&mut self, ctx: &mut Ctx) -> Flow {
        let pushed = std::mem::replace(&mut self.pushed, Pushed::None);
        if self.end.is_some() {
            return Flow::Stay;
        }
        match pushed {
            Pushed::None => Flow::Stay,
            Pushed::Ask => {
                let task = self.task();
                let name = task
                    .asks
                    .as_ref()
                    .map(|a| a.name.as_str())
                    .unwrap_or_default();
                // Unanswered, as an unattended run leaves it, skips the task.
                if ctx.store.get(name).is_empty() {
                    crate::info!("{}: skipped", task.title);
                    self.marks[self.at] = Mark::Skipped;
                    self.advance();
                    return self.step(ctx);
                }
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

    /// Ends the run in place. Later task events, answers and ticks do not advance it.
    fn stop(&mut self, ctx: &mut Ctx) -> Option<Session> {
        if self.end.is_some() {
            return None;
        }
        let session = self.session.take();
        self.finish(Err(End::Stopped), ctx);
        session
    }

    fn animating(&self, _: &Ctx) -> bool {
        self.end.is_none() || !self.settled()
    }
}

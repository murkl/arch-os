//! Pages and their two chains: the opening and the start.

pub mod action;
pub mod confirm;
pub mod dashboard;
pub mod failure;
pub mod gate;
pub mod language;
pub mod leave;
pub mod password;
pub mod presets;
pub mod question;
pub mod report;
pub mod results;
pub mod run;
pub mod splash;

use super::{Ctx, Flow};
use crate::spec::Action;

/// What follows an answered question.
#[derive(Clone, Debug, PartialEq)]
pub enum Then {
    /// Next step of the opening: question, gate, profiles, dashboard.
    Opening,
    /// Next step of the start: open question, passwords, confirmation.
    Start,
    /// Back to the page that opened it, which reads the answer.
    Pop,
    /// Next page of an action: inputs from `next` on, confirmation, run.
    Action {
        action: &'static Action,
        next: usize,
        depth: usize,
        fetches: bool,
    },
}

pub fn after(then: &Then, ctx: &mut Ctx) -> Flow {
    match then {
        Then::Opening => next(ctx),
        Then::Start => start(ctx),
        Then::Pop => Flow::Pop,
        Then::Action {
            action: it,
            next,
            depth,
            fetches,
        } => Flow::Push(action::page(ctx, it, *next, *depth, *fetches)),
    }
}

/// Next opening step: upfront questions, gate, a profile on a machine without answers, then the
/// open questions, numbered. Steps with nothing to ask are skipped.
pub fn next(ctx: &mut Ctx) -> Flow {
    if let Some(s) = ctx.store.upfront().first() {
        return Flow::Push(Box::new(question::QuestionPage::setting(s, Then::Opening)));
    }
    if !ctx.gated && !ctx.module.requires.is_empty() && !ctx.store.dry_run() {
        return Flow::Push(Box::new(gate::GatePage::new()));
    }
    if ctx.first && !ctx.presets_seen && !ctx.module.presets.is_empty() {
        return Flow::Push(Box::new(presets::PresetsPage::new()));
    }
    let missing = ctx.store.missing();
    if let Some(s) = missing.first() {
        if ctx.wizard == 0 {
            ctx.wizard = missing.len();
        }
        return Flow::Push(Box::new(question::QuestionPage::setting(s, Then::Opening)));
    }
    ctx.wizard = 0;
    Flow::Home
}

/// Next start step: open questions, passwords, confirmation, run.
pub fn start(ctx: &mut Ctx) -> Flow {
    if let Some(s) = ctx.store.missing().first() {
        return Flow::Push(Box::new(question::QuestionPage::setting(s, Then::Start)));
    }
    if let Some(s) = ctx
        .store
        .secrets()
        .into_iter()
        .find(|s| ctx.store.get(&s.name).is_empty())
    {
        return Flow::Push(Box::new(password::PasswordPage::new(s, Then::Start)));
    }
    if let Some(text) = &ctx.module.confirm {
        return Flow::Push(Box::new(confirm::YesNoPage::start(ctx, text)));
    }
    Flow::Push(Box::new(run::RunPage::new(ctx)))
}

/// Question counter of the opening, for the header.
pub fn counter(ctx: &Ctx) -> Option<String> {
    if ctx.wizard == 0 {
        return None;
    }
    let left = ctx.store.missing().len();
    let at = (ctx.wizard + 1).saturating_sub(left).max(1);
    let of = ctx.wizard.max(at + left - 1);
    Some(crate::i18n::tf(
        "{{at}} of {{of}}",
        &[("at", &at), ("of", &of)],
    ))
}

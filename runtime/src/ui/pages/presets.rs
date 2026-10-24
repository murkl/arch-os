//! Profiles, offered once on a machine without answers. A profile only sets ordinary answers,
//! so a keypress does nothing irreversible.

use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

use crate::i18n::t;
use crate::ui::draw::paragraph;
use crate::ui::list::{List, Picked, Row};
use crate::ui::{Ctx, Flow, Key, Page, Tone};

pub struct PresetsPage {
    list: List<usize>,
}

impl PresetsPage {
    pub fn new() -> PresetsPage {
        PresetsPage {
            list: List::default(),
        }
    }

    /// Applies the profile's answers and moves on to the next opening step.
    fn taken(ctx: &mut Ctx) -> Flow {
        ctx.presets_seen = true;
        ctx.settle();
        ctx.resolve();
        ctx.save();
        match super::next(ctx) {
            Flow::Push(page) => Flow::Replace(page),
            flow => flow,
        }
    }
}

impl Page for PresetsPage {
    /// Only shown without an answer file.
    fn unattended(&mut self, _: &mut Ctx) -> Result<Flow, String> {
        Err(crate::i18n::t("No answer file."))
    }

    fn title(&self) -> String {
        t("Profile")
    }

    fn draw(&mut self, area: Rect, buf: &mut Buffer, ctx: &mut Ctx) {
        if self.list.rows().is_empty() {
            let rows = ctx
                .module
                .presets
                .iter()
                .enumerate()
                .map(|(i, p)| Row::new(i, t(&p.title)).describe(t(&p.description)))
                .collect();
            self.list = List::new(rows);
            self.list.described = true;
        }
        let text = t("Prefills every answer.");
        let y = paragraph(buf, area, area.y, &text, ctx.style.tone(Tone::Muted)) + 1;
        self.list.draw(
            Rect::new(area.x, y, area.width, area.bottom().saturating_sub(y)),
            buf,
            ctx,
        );
    }

    fn hints(&self, _: &Ctx) -> Vec<(&'static str, String)> {
        vec![("↑↓", t("choose")), ("⏎", t("confirm")), ("esc", t("back"))]
    }

    fn key(&mut self, key: Key, ctx: &mut Ctx) -> Flow {
        match self.list.key(key) {
            Picked::Open(i) => {
                let preset = &ctx.module.presets[i];
                crate::info!("profile: {}", preset.title);
                match &preset.action {
                    Some(id) => {
                        let action = ctx
                            .module
                            .action(id)
                            .expect("a preset names an action that exists");
                        super::action::open(ctx, action, true)
                    }
                    None => {
                        ctx.store.apply(preset);
                        PresetsPage::taken(ctx)
                    }
                }
            }
            Picked::Used => Flow::Stay,
            Picked::Ignored => Flow::Ignored,
        }
    }

    fn root(&self) -> bool {
        true
    }

    /// After the fetch action, reloads its answer file over the held answers and applies them, like
    /// a local profile.
    fn resumed(&mut self, ctx: &mut Ctx) -> Flow {
        if !ctx.imported {
            return Flow::Stay;
        }
        ctx.imported = false;
        if let Err(e) = ctx.store.load() {
            crate::error!("{}: {e}", ctx.store.path().display());
        }
        PresetsPage::taken(ctx)
    }
}

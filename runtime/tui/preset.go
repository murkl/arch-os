package tui

import (
	"github.com/murkl/arch-os/runtime/internal/spec"

	tea "github.com/charmbracelet/bubbletea"
)

// presetScreen is one of the questions a fresh machine is asked before the real
// ones: where it is, what kind of system it is going to be. What the page is
// called and what it says come from the module, because what a starting point
// stands for is the module's own business.
//
// A preset is a set of answers, not a mode. Choosing one fills in what that
// kind of installation usually wants and then stops mattering — every value it
// set is an ordinary value from the next page on, and the settings page will
// not remember which of them came from here. That is the whole reason this can
// be one keypress: nothing it does is hard to undo.
type presetScreen struct {
	opening
	app    *app
	preset *spec.Preset
	done   func() tea.Cmd
	picker *picker
}

func newPreset(a *app, p *spec.Preset, done func() tea.Cmd) *presetScreen {
	s := &presetScreen{app: a, preset: p, done: done}
	items := make([]item, 0, len(p.Options))
	for _, o := range p.Options {
		items = append(items, item{title: o.Label(), detail: o.Help(), key: o.ID})
	}
	s.picker = newPicker(items)
	s.picker.describe(p.Help())
	return s
}

func (s *presetScreen) Title() string { return s.preset.Label() }
func (s *presetScreen) Hint() string  { return labelHintChoose() }

func (s *presetScreen) Update(msg tea.Msg) (screen, tea.Cmd) {
	s.picker.Update(msg)
	key, ok := msg.(tea.KeyMsg)
	if !ok {
		return s, nil
	}
	switch {
	case confirms(key):
		id := s.picker.selected()
		if id == "" {
			return s, nil
		}
		for _, o := range s.preset.Options {
			if o.ID == id {
				return s, s.take(o)
			}
		}
		return s, nil
	case backs(key):
		return s, pop()
	}
	return s, nil
}

// take is a starting point being chosen: its values become answers, and the
// page after it is the next one.
//
// A row that asks something first is the same idea reached the long way round.
// A starting point somebody was handed rather than picked off this page — a
// configuration shared after another installation — is one question and then
// exactly the same set of answers, so it is one more row here and not a mode,
// a flag or a page of its own. What it asks is asked on the page every other
// question is asked on, and what the answer stands for is fetched by the
// module's own shell, since only the module knows where such a thing is kept.
func (s *presetScreen) take(o *spec.PresetOption) tea.Cmd {
	if !o.Fetches() {
		return tea.Batch(s.app.adopt(o), s.done())
	}
	return push(newField(s.app, s.app.module.Var(o.Asks), func() tea.Cmd {
		return tea.Batch(s.app.adopt(o), s.done())
	}).opening().importing(o.Apply))
}

func (s *presetScreen) View(width, height int) string {
	return withDetail(s.picker, width, height)
}

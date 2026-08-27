package tui

import (
	"installer/internal/spec"

	tea "github.com/charmbracelet/bubbletea"
)

// presetScreen is one of the questions a fresh machine is asked before the real
// ones: where it is, what kind of system it is going to be. What the page is
// called and what it says come from the tree, because what a starting point
// stands for is the tree's own business.
//
// A preset is a set of answers, not a mode. Choosing one fills in what that
// kind of installation usually wants and then stops mattering — every value it
// set is an ordinary value from the next page on, and the settings page will
// not remember which of them came from here. That is the whole reason this can
// be one keypress: nothing it does is hard to undo.
type presetScreen struct {
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
				return s, tea.Batch(s.app.adopt(o), s.done())
			}
		}
		return s, nil
	case backs(key):
		return s, pop()
	}
	return s, nil
}

func (s *presetScreen) View(width, height int) string {
	return withDetail(s.picker, width, height)
}

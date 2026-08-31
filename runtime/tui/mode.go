package tui

import (
	"installer/internal/spec"

	tea "github.com/charmbracelet/bubbletea"
)

// modeScreen is the fork at the top of the program: which of the things this
// tree can do is this run.
//
// It comes after the few questions the tree marks `first` and before everything
// else, because everything else follows from it — which questions are worth
// asking, whether a network matters, what the check is a check of. What is on
// offer is the tree's own list, so the runtime never learns the name of any of
// it.
//
// The cursor opens on whatever was chosen last, and on a machine that has never
// chosen anything on the first mode the tree names. There is always an answer
// under the cursor, so the page can be got past with one key.
type modeScreen struct {
	app    *app
	picker *picker
	done   func() tea.Cmd
}

func newMode(a *app, done func() tea.Cmd) *modeScreen {
	s := &modeScreen{app: a, done: done}
	items := make([]item, 0, len(a.spec.Modes))
	for _, m := range a.spec.Modes {
		items = append(items, item{title: m.Label(), detail: m.Help(), key: m.ID})
	}
	s.picker = newPicker(items)
	s.picker.focus(a.mode().ID)
	return s
}

func (s *modeScreen) Title() string { return labelMode() }
func (s *modeScreen) Hint() string  { return labelHintChoose() }

func (s *modeScreen) Update(msg tea.Msg) (screen, tea.Cmd) {
	s.picker.Update(msg)
	key, ok := msg.(tea.KeyMsg)
	if !ok {
		return s, nil
	}
	switch {
	case confirms(key):
		id, ok := s.picker.chosen()
		if !ok {
			return s, nil
		}
		s.app.store.Set(spec.ModeVar, id)
		return s, tea.Batch(s.app.save(), s.done())
	case backs(key):
		return s, pop()
	}
	return s, nil
}

func (s *modeScreen) View(width, height int) string {
	return withDetail(s.picker, width, height)
}

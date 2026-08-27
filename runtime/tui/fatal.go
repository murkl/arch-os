package tui

import tea "github.com/charmbracelet/bubbletea"

// fatalScreen is the end of the road: something the program cannot work around
// and the user cannot answer. It offers exactly one thing, which is to leave.
type fatalScreen struct {
	app *app
	err error
}

func newFatal(a *app, err error) *fatalScreen { return &fatalScreen{app: a, err: err} }

func (s *fatalScreen) Title() string { return "" }
func (s *fatalScreen) Hint() string  { return s.app.hintEnd(labelHintQuit()) }

func (s *fatalScreen) Update(msg tea.Msg) (screen, tea.Cmd) {
	key, ok := msg.(tea.KeyMsg)
	if !ok {
		return s, nil
	}
	// Deliberately answers, not any key: this page arrives while somebody is
	// still typing at the page before it, and a stray keystroke must not close
	// the one explanation they are going to get.
	if answers(key) {
		return s, leave()
	}
	return s, nil
}

func (s *fatalScreen) View(width, height int) string {
	head := failStyle.Render(glyphs.fail) + field(" ") + boldStyle.Render(labelCannotContinue())
	return head + "\n\n" + renderFailure(s.err, width)
}

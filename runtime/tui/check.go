package tui

import (
	"installer/internal/logging"

	tea "github.com/charmbracelet/bubbletea"
)

// checkScreen is the folder's own verdict on whether this machine can be
// installed onto at all, run before anything is asked bar the few questions the
// folder marks `first`.
//
// It gets a page rather than a pause because it can take a while — a folder
// will want to wait for a network — and a minute of nothing on screen is
// indistinguishable from a program that has hung. A page with a turning mark on
// it is a program working.
type checkScreen struct {
	opening
	app  *app
	done bool
}

func newCheck(a *app) *checkScreen { return &checkScreen{app: a} }

func (s *checkScreen) Title() string { return "" }
func (s *checkScreen) Hint() string  { return labelHintRunning() }

// working is what puts the mark in the header while the check runs.
func (s *checkScreen) working() bool { return !s.done }

type checkedMsg struct{ err error }

func (s *checkScreen) Init() tea.Cmd {
	return func() tea.Msg { return checkedMsg{s.app.runner.Preflight()} }
}

func (s *checkScreen) Update(msg tea.Msg) (screen, tea.Cmd) {
	c, ok := msg.(checkedMsg)
	if !ok {
		return s, nil
	}
	s.done = true
	if c.err != nil {
		logging.Error("%s", c.err)
		// A wall, not a warning. Nothing this program could offer next would be
		// safe on a machine its own folder has just said no to, so the stack is
		// replaced rather than added to: there is no page behind this one to go
		// back to.
		return s, reset(newFatal(s.app, c.err))
	}
	return s, reset(s.app.afterCheck())
}

func (s *checkScreen) View(width, height int) string {
	return accentStyle.Render(spinFrame()) + field(" ") + boldStyle.Render(labelChecking())
}

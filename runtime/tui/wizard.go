package tui

import (
	"installer/internal/spec"

	tea "github.com/charmbracelet/bubbletea"
)

// wizard is the opening run of questions: every value that is required, means
// something, and has no acceptable answer yet — asked one to a page, in the
// order the folder declared them.
//
// It is not a screen. It is the thing that decides which screen comes next, and
// it holds nothing but the length of the run it started with. What is still
// open is read from the answers every single time rather than remembered,
// because answering one question can open another — say yes to a desktop and
// there is suddenly a graphics driver to choose — and a list worked out once at
// the start would quietly skip it.
type wizard struct {
	app   *app
	total int
}

func newWizard(a *app) *wizard {
	return &wizard{app: a, total: len(a.store.Missing())}
}

// screen is the page for one question, numbered within the run.
func (w *wizard) screen(v *spec.Variable) screen {
	at, of := w.place()
	return newField(w.app, v, w.next).counted(at, of)
}

// next is what follows an answer: the question after it, or the end of the run.
// Reached again by answering a question a second time — somebody went back a
// page — and correct there too, because where a question sits is worked out
// from what is still open rather than counted off as pages go by.
func (w *wizard) next() tea.Cmd {
	missing := w.app.store.Missing()
	if len(missing) == 0 {
		// Nothing left open: the stack of questions goes with it, so the hub is
		// the whole of what is on screen and esc there means leaving the program
		// rather than walking back through answers already given.
		return reset(newHub(w.app))
	}
	return push(w.screen(missing[0]))
}

// place is where the question about to be asked sits in the run, counting from
// one. Derived, never counted: the length can grow as answers open further
// questions, and the position has to stay right when somebody goes back.
func (w *wizard) place() (at, of int) {
	left := len(w.app.store.Missing())
	at = max(w.total-left+1, 1)
	return at, max(w.total, at+left-1)
}

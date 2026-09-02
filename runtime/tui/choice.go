package tui

import (
	"installer/internal/spec"

	tea "github.com/charmbracelet/bubbletea"
)

// choiceScreen is the front door of a release that holds more than one program:
// which of the trees beside the binary this run is.
//
// It comes before everything else, because everything else belongs to whichever
// it settles — the questions, the answer file, the log, the words on screen. An
// installer that can also repair what it installed is not one program with a
// switch in it: the two ask different questions, do different work and are
// dangerous in different ways, so they are two trees and this is the one moment
// they are told apart.
//
// What is on offer is each tree's own name and its own sentence about itself, so
// the runtime never learns what any of them is for. A release holding one tree
// never draws this page.
type choiceScreen struct {
	opening
	app    *app
	picker *picker
	done   func() tea.Cmd
}

func newChoice(a *app, done func() tea.Cmd) *choiceScreen {
	s := &choiceScreen{app: a, done: done}
	items := make([]item, 0, len(a.trees))
	for _, sp := range a.trees {
		items = append(items, item{title: sp.Name(), detail: sp.Help(), key: sp.Dir})
	}
	s.picker = newPicker(items)
	return s
}

func (s *choiceScreen) Title() string { return labelChoice() }
func (s *choiceScreen) Hint() string  { return labelHintChoose() }

func (s *choiceScreen) Update(msg tea.Msg) (screen, tea.Cmd) {
	s.picker.Update(msg)
	key, ok := msg.(tea.KeyMsg)
	if !ok {
		return s, nil
	}
	if !confirms(key) {
		return s, nil
	}
	dir, ok := s.picker.chosen()
	if !ok {
		return s, nil
	}
	// A tree that will not open is the end of the road rather than a row that
	// does nothing: it was read and checked at startup, so anything failing here
	// is the machine refusing to keep the answers or the log.
	if err := s.app.enter(s.app.tree(dir)); err != nil {
		return s, push(newFatal(s.app, err))
	}
	return s, s.done()
}

func (s *choiceScreen) View(width, height int) string {
	return withDetail(s.picker, width, height)
}

// tree is the program a row on that page stands for.
func (a *app) tree(dir string) *spec.Spec {
	for _, sp := range a.trees {
		if sp.Dir == dir {
			return sp
		}
	}
	return nil
}

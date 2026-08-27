package tui

import (
	tea "github.com/charmbracelet/bubbletea"
)

// hub is where a machine that has answered everything waits: two things to do,
// and no way to get lost between them. Install, or go through the answers
// again.
//
// It has no description of its own and needs none — two rows, each with a
// sentence under it, say the whole of what this page is.
type hub struct {
	app    *app
	picker *picker
}

// The two rows. The NUL prefix cannot collide with anything the folder names.
const (
	keyInstall  = "\x00install"
	keySettings = "\x00settings"
)

func newHub(a *app) *hub {
	h := &hub{app: a}
	h.build()
	return h
}

func (h *hub) Refresh() {
	key := h.picker.selected()
	h.build()
	h.picker.focus(key)
}

func (h *hub) build() {
	h.picker = newPicker([]item{
		{title: labelInstall(), detail: labelInstallHelp(), key: keyInstall},
		{title: labelSettings(), detail: labelSettingsHelp(), key: keySettings},
	})
}

func (h *hub) Title() string { return "" }
func (h *hub) Hint() string  { return labelHintMenu() }

func (h *hub) Update(msg tea.Msg) (screen, tea.Cmd) {
	h.picker.Update(msg)
	key, ok := msg.(tea.KeyMsg)
	if !ok {
		return h, nil
	}
	switch {
	case confirms(key):
		switch h.picker.selected() {
		case keyInstall:
			return h, push(newConfirm(h.app))
		case keySettings:
			return h, push(newSettings(h.app))
		}
	case key.String() == "q", cancels(key):
		return h, leave()
	}
	return h, nil
}

func (h *hub) View(width, height int) string { return withDetail(h.picker, width, height) }

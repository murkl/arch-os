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

// build names the top row after whatever this run is doing. A tree that names
// its run has already said what it is called and what it does, in its own
// words — and the row that starts one should be read in those words rather than
// in the runtime's guess at them.
func (h *hub) build() {
	title, detail := labelInstall(), labelInstallHelp()
	if name := h.app.spec.RunName(); name != "" {
		title, detail = name, h.app.spec.Help()
	}
	h.picker = newPicker([]item{
		{title: title, detail: detail, key: keyInstall},
		{title: labelSettings(), detail: labelSettingsHelp(h.app.spec.Name()), key: keySettings},
	})
}

func (h *hub) Title() string { return "" }
func (h *hub) Hint() string  { return labelHintMenu() }

// crumbRoot: the hub is home. Whatever run of pages ended on it is over, and
// none of it is behind this page any more.
func (h *hub) crumbRoot() bool { return true }

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

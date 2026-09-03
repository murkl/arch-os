package tui

import (
	"strings"

	"github.com/murkl/arch-os/runtime/internal/spec"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
)

// secretScreen asks for a value that is never written down.
//
// Twice, always, and that is not a setting: a password typed once and mistyped
// is discovered at the first boot of a system that took twenty minutes to
// build. The second entry costs four seconds.
//
// What is typed reaches exactly one place — the environment of the bash process
// that runs the stages. Not the answer file, not the log, not the argument list
// of anything, and not the screen, which shows one dot per character.
type secretScreen struct {
	app  *app
	v    *spec.Variable
	done func() tea.Cmd

	input   textinput.Model
	first   string
	again   bool
	problem string
}

func newSecret(a *app, v *spec.Variable, done func() tea.Cmd) *secretScreen {
	s := &secretScreen{app: a, v: v, done: done}
	s.box()
	return s
}

// box is a fresh, empty entry field. Fresh every time rather than cleared: the
// repeat has to be typed, never edited from what the first entry left behind.
func (s *secretScreen) box() {
	s.input = textinput.New()
	s.input.EchoMode = textinput.EchoPassword
	s.input.EchoCharacter = []rune(glyphs.secret)[0]
	s.input.CharLimit = 128
	styleInput(&s.input)
	s.input.Focus()
}

func (s *secretScreen) Init() tea.Cmd { return textinput.Blink }

func (s *secretScreen) Title() string { return s.v.Label() }
func (s *secretScreen) Hint() string  { return labelHintInput() }

func (s *secretScreen) Update(msg tea.Msg) (screen, tea.Cmd) {
	key, ok := msg.(tea.KeyMsg)
	if !ok {
		return s, nil
	}
	switch {
	case cancels(key), erases(key) && s.input.Value() == "":
		// Backing out of the repeat goes back to the first entry, not out of the
		// page: the two are one question.
		if s.again {
			s.again, s.problem = false, ""
			s.first = ""
			s.box()
			return s, nil
		}
		return s, pop()
	case confirms(key):
		return s.commit()
	}
	var cmd tea.Cmd
	s.input, cmd = s.input.Update(key)
	return s, cmd
}

func (s *secretScreen) commit() (screen, tea.Cmd) {
	value := s.input.Value()
	if !s.again {
		if value == "" && s.v.Required {
			s.problem = s.v.Why()
			return s, nil
		}
		s.first, s.again, s.problem = value, true, ""
		s.box()
		return s, nil
	}
	if value != s.first {
		// Back to the beginning rather than asking for the repeat again: one of
		// the two was wrong and there is no telling which.
		s.first, s.again = "", false
		s.problem = labelPasswordMismatch()
		s.box()
		return s, nil
	}
	s.app.store.Set(s.v.Name, value)
	return s, s.done()
}

func (s *secretScreen) View(width, height int) string {
	var b strings.Builder
	if help := s.v.Help(); help != "" {
		b.WriteString(paragraph(help, width) + "\n\n")
	}
	label := s.v.Label()
	if s.again {
		label = labelPasswordRepeat()
	}
	b.WriteString(softStyle.Render(label) + "\n")
	b.WriteString(cursorStyle.Render(glyphs.cursor) + s.input.View())
	if s.problem != "" {
		b.WriteString("\n\n" + failStyle.Render(truncate(s.problem, width)))
	}
	return b.String()
}

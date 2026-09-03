package tui

import (
	"strings"

	"github.com/murkl/arch-os/runtime/internal/logging"
	"github.com/murkl/arch-os/runtime/internal/spec"

	tea "github.com/charmbracelet/bubbletea"
)

// leaveScreen is the way out, on a machine where leaving is not quitting a
// program.
//
// A module with a restart or a shutdown hook is saying that this machine booted
// to run it: quitting into whatever is behind it is not an exit unless there is
// something there. So every way out of the interface arrives here instead, and
// what is offered is what this machine can actually be left in — off, starting
// again, or, where the module names a console to go back to, running with the
// interface closed.
//
// It is drawn over whatever was happening rather than in place of it, and
// nothing is stopped by its appearing: a run carries on behind it and the
// header keeps counting. Choosing a row is what stops it — that is what halt
// is, and it is called before any of the three does anything else.
//
// The hooks are the module's, which is also what makes them harmless while one
// is being tried out: a module that simulates its work simulates this too, and
// the program simply closes.
type leaveScreen struct {
	app    *app
	halt   func()
	picker *picker

	// doing is the row being carried out, empty while nothing is. A restart
	// takes a moment to arrive and the frame has to say something in it, or the
	// last thing anybody sees is a page that ignored their keystroke.
	doing string
	err   error
}

// The rows. The NUL prefix cannot collide with anything a module names.
const (
	keyRestart  = "\x00restart"
	keyShutdown = "\x00shutdown"
	keyConsole  = "\x00console"
)

func newLeave(a *app, halt func(), running bool) *leaveScreen {
	s := &leaveScreen{app: a, halt: halt}
	var items []item
	// Only what the module actually has: a row that would run nothing is a row
	// that reads as a machine refusing to switch off.
	if a.module.Hook(spec.HookRestart) != "" {
		items = append(items, item{title: labelRestart(), detail: labelRestartHelp(), key: keyRestart})
	}
	if a.module.Hook(spec.HookShutdown) != "" {
		items = append(items, item{title: labelShutdown(), detail: labelShutdownHelp(), key: keyShutdown})
	}
	// Last, and only where the module names a way back: the two rows above end
	// this machine's session, and this one only ends the program. It reads as
	// the smallest of the three and belongs under them.
	if a.module.UI.Console != "" {
		items = append(items, item{
			title:  labelConsole(),
			detail: a.module.ConsoleHelp(),
			key:    keyConsole,
		})
	}
	s.picker = newPicker(items)
	// Said out loud only while there is something to say it about: whoever
	// reached this page in the middle of a run is owed both halves of it — that
	// the run did not stop, and that every row here stops it.
	if running {
		s.picker.describe(labelLeaveRunning())
	}
	return s
}

func (s *leaveScreen) Title() string { return labelLeave() }

func (s *leaveScreen) Hint() string {
	if s.doing != "" {
		return labelHintRunning()
	}
	return labelHintChoose()
}

// working is what puts the turning mark in the header while a machine is on its
// way down.
func (s *leaveScreen) working() bool { return s.doing != "" }

// leftMsg is the command coming back, which on a machine that is genuinely
// going down never happens: systemd takes the program with it long before.
// It arrives when something went wrong, and when nothing was really done —
// an installer being tried out.
type leftMsg struct{ err error }

func (s *leaveScreen) Update(msg tea.Msg) (screen, tea.Cmd) {
	switch msg := msg.(type) {
	case leftMsg:
		s.doing = ""
		if msg.err != nil {
			// Nothing else to do but say so and stand here: the machine is
			// still running, and the other row may still work.
			logging.Error("%s", msg.err)
			s.err = msg.err
			return s, nil
		}
		return s, quit()

	case tea.KeyMsg:
		// Nothing means anything while the machine is going down. It is about to
		// stop answering, and a keystroke that started a second command into
		// that would be the one thing that could still go wrong.
		if s.doing != "" {
			return s, nil
		}
		s.picker.Update(msg)
		switch {
		case confirms(msg):
			return s, s.carryOut(s.picker.selected())
		case backs(msg):
			// Back to whatever this was drawn over — the hub, a question, an
			// installation that has been running the whole time this page was
			// up. Nothing was stopped to get here, so there is nothing to
			// restore.
			return s, dismiss()
		}
	}
	return s, nil
}

// carryOut runs the module's own command for a row and reports back. It is not a
// task and does not belong in a run: nothing follows it, there is nothing to
// report to a list, and the log is the only place a failure could be written
// down anyway.
func (s *leaveScreen) carryOut(key string) tea.Cmd {
	if key == "" {
		return nil
	}
	// From here on this is a decision rather than a question, so whatever was
	// running behind this page is put down first — all three rows end it.
	s.halt()
	// The console is not a command and nothing is waiting for it: the program
	// closes, and the sentence the module wrote is printed where the frame was —
	// the first thing on the terminal somebody is left looking at.
	if key == keyConsole {
		s.app.farewell = s.app.module.ConsoleHelp()
		return quit()
	}
	s.doing, s.err = key, nil
	restart := key == keyRestart
	return func() tea.Msg { return leftMsg{s.app.runner.Leave(restart)} }
}

func (s *leaveScreen) View(width, height int) string {
	if s.doing != "" {
		word := labelShuttingDown()
		if s.doing == keyRestart {
			word = labelRestarting()
		}
		return accentStyle.Render(spinFrame()) + field(" ") + boldStyle.Render(word)
	}
	var b strings.Builder
	if s.err != nil {
		head := failStyle.Render(glyphs.fail) + field(" ") + boldStyle.Render(labelLeaveFailed())
		b.WriteString(head + "\n\n" + renderFailure(s.err, width) + "\n\n")
		height -= strings.Count(b.String(), "\n")
	}
	return b.String() + withDetail(s.picker, width, height)
}

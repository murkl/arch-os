package tui

import (
	"fmt"
	"strings"
	"time"

	"installer/internal/exec"
	"installer/internal/logging"
	"installer/internal/spec"

	tea "github.com/charmbracelet/bubbletea"
)

// runScreen runs the tasks, one after another, and shows how far it has got. It
// is the installation, from the first partition to whatever the tree offers
// once the system is on the disk.
//
// What it shows is a list of names with a mark against each. What it does not
// show is a single line of what any of them printed: a package manager's
// progress bars, a compiler's warnings and a bootloader's chatter are not
// information here, they are noise with escape codes in it, and the frame is
// the promise that none of it gets out. All of it goes to the log, which is
// where anyone chasing a detail was always going to look.
//
// The one thing that interrupts the list is a task that asks first. That is how
// a tree offers something rather than does it — reboot now, unmount, drop into
// the new system — without any of them being a page of their own.
type runScreen struct {
	app *app

	// title names this run in the log. What is on screen says the same thing in
	// the interface's own words and with the clock on it — see headline.
	title string

	steps []*spec.Task
	state []mark

	// Where the two outcomes lead. Both are given by whoever started the run,
	// because only they know what a success means next and where a failure is
	// fixed — an installation that fails belongs back among the answers.
	then func() tea.Cmd
	back func() tea.Cmd

	at      int // the task running now, or len(steps) once they all have
	asking  *picker
	session *exec.Session
	err     error
	done    bool

	// settled is whether a keystroke means anything yet. It is false while
	// something is running and for a moment after every question and every
	// result — see settleFor.
	settled bool

	// When the run began, and how long it turned out to take. Read from the wall
	// clock rather than counted off the frames: the frames stop while a task
	// asks and while one has the terminal to itself, and an installation is not
	// shorter for having waited for somebody.
	started time.Time
	took    time.Duration
}

// mark is what a row has against it, which is also the whole of a run's state.
type mark int

const (
	pending mark = iota
	ran
	skipped
)

// settleFor is the pause before a keystroke counts, after a question appears
// and after the run ends.
//
// An installation takes minutes and people press keys while they wait. Those
// keystrokes sit in the terminal's buffer and arrive the instant the screen
// changes — without this pause the result of a twenty-minute install would be
// gone before it had been on screen for a frame, and a question nobody had read
// yet would be answered by an enter meant for something else entirely.
const settleFor = 618 * time.Millisecond

func newRun(a *app, title string, steps []*spec.Task, then, back func() tea.Cmd) *runScreen {
	return &runScreen{app: a, title: title, steps: steps, state: make([]mark, len(steps)), then: then, back: back}
}

func (s *runScreen) Title() string { return "" }

// crumbRoot: a run is not a place you navigated to, it is a thing happening.
// The trail of pages that led here — a confirmation, a password — is spent, and
// leaving it standing would be a line of the frame saying where you no longer
// are. Titling itself nothing then leaves the row to the list.
func (s *runScreen) crumbRoot() bool { return true }

// working is what puts the turning mark in the header: something is running,
// which a question waiting for an answer is not.
func (s *runScreen) working() bool { return !s.done && s.asking == nil }

// status is the counter beside it: which step of how many.
func (s *runScreen) status() string {
	if s.done {
		return ""
	}
	return labelCounter(min(s.at+1, len(s.steps)), len(s.steps))
}

func (s *runScreen) Hint() string {
	switch {
	case s.asking != nil:
		return labelHintChoose()
	case !s.settled:
		return labelHintRunning()
	case s.err != nil:
		return labelHintBack()
	}
	return s.app.hintEnd(labelHintClose())
}

func (s *runScreen) Init() tea.Cmd {
	s.started = time.Now()
	return s.step()
}

// elapsed is how long this run has been going, and how long it went for once it
// is over — one answer, so the headline reads the same number before and after.
func (s *runScreen) elapsed() time.Duration {
	if s.done {
		return s.took
	}
	return time.Since(s.started)
}

// clock renders a duration the way a clock does: minutes and seconds, with
// hours in front of them once there are any. An installation is measured in
// minutes, so that is the unit it is read in — and one that runs past an hour
// has to say so rather than counting up to 74 minutes.
func clock(d time.Duration) string {
	if d < 0 {
		d = 0
	}
	secs := int(d.Seconds())
	if hours := secs / 3600; hours > 0 {
		return fmt.Sprintf("%d:%02d:%02d", hours, secs/60%60, secs%60)
	}
	return fmt.Sprintf("%02d:%02d", secs/60, secs%60)
}

type (
	stepDoneMsg struct{ err error }
	settleMsg   struct{}
)

// step takes on the task at the cursor: asks about it if it is an offer,
// runs it if it is not, and ends the run when there are none left.
//
// Each is started from here rather than from a loop, so the frame is redrawn
// between them and the list is always showing the truth.
func (s *runScreen) step() tea.Cmd {
	if s.at >= len(s.steps) {
		return s.finish(nil)
	}
	if e := s.steps[s.at]; e.Asks() {
		s.asking = newPicker([]item{
			{title: labelYes(), key: keyYes},
			{title: labelNo(), key: keyNo},
		})
		return s.settle()
	}
	return s.start()
}

// start runs the task at the cursor, either in the background like every
// other one or by handing it the terminal.
func (s *runScreen) start() tea.Cmd {
	s.settled = false
	e := s.steps[s.at]
	if e.TTY {
		// The interface stands down for the length of this one: bubbletea
		// releases the terminal, the script has it whole, and the frame is
		// restored exactly as it was when the script exits.
		return tea.ExecProcess(s.app.runner.Terminal(e), func(err error) tea.Msg {
			return stepDoneMsg{exec.Fail(e.Label(), err)}
		})
	}
	session, err := s.app.runner.Start(e)
	if err != nil {
		return s.finish(err)
	}
	s.session = session
	// No clock of its own: the frame already repaints while a page reports it is
	// working, which is what makes the clock in the headline count rather than
	// sit at the second the run began.
	return waitFor(session)
}

func waitFor(session *exec.Session) tea.Cmd {
	return func() tea.Msg {
		<-session.Done()
		return stepDoneMsg{session.Err()}
	}
}

// finish ends the run, one way or the other.
func (s *runScreen) finish(err error) tea.Cmd {
	s.took = time.Since(s.started)
	s.done, s.err, s.session, s.asking = true, err, nil, nil
	if err != nil {
		logging.Error("%s", err)
	} else {
		logging.Info("%s: ok", s.title)
	}
	// Whatever a run was given is gone the moment it is over, whether it worked
	// or not: a failed installation is one that gets looked at, and nothing
	// typed in confidence should still be in memory while that happens.
	s.app.store.Forget()
	return s.settle()
}

// settle starts the clock that makes what is on screen answerable.
func (s *runScreen) settle() tea.Cmd {
	s.settled = false
	return tea.Tick(settleFor, func(time.Time) tea.Msg { return settleMsg{} })
}

// stop kills the task that is running, and everything it started. Reached
// only by ctrl+c, which is the one key that works while a run is going and
// which somebody has to mean.
func (s *runScreen) stop() {
	if s.session != nil {
		logging.Warn("%s: stopped", s.title)
		s.session.Kill()
	}
}

func (s *runScreen) Update(msg tea.Msg) (screen, tea.Cmd) {
	switch msg := msg.(type) {
	case stepDoneMsg:
		if msg.err != nil {
			return s, s.finish(msg.err)
		}
		s.state[s.at] = ran
		// A task the program does not come back from — a reboot — ends it
		// here rather than carrying on into a list nobody will ever see again.
		if s.steps[s.at].Quits {
			return s, quit()
		}
		s.at++
		return s, s.step()

	case settleMsg:
		s.settled = true
		return s, nil

	case tea.KeyMsg:
		if !s.settled {
			// Killing a half-finished package transaction is worse than waiting
			// for it, so the only way out while it runs is ctrl+c, which the
			// model handles and which somebody has to mean.
			return s, nil
		}
		if s.asking != nil {
			return s, s.answer(msg)
		}
		// The result is dismissed deliberately or not at all: enter and esc,
		// nothing else. Every other key — and every scroll, which arrives here
		// as an arrow — leaves the report on screen.
		if answers(msg) {
			if s.err != nil {
				return s, s.back()
			}
			return s, s.then()
		}
	}
	return s, nil
}

// answer takes the yes or no to a task that asked. No is an answer like any
// other: the task is skipped, and the run carries on.
func (s *runScreen) answer(key tea.KeyMsg) tea.Cmd {
	s.asking.Update(key)
	if !confirms(key) {
		return nil
	}
	yes := s.asking.selected() == keyYes
	s.asking = nil
	if yes {
		return s.start()
	}
	logging.Info("%s: declined", s.steps[s.at].Name)
	s.state[s.at] = skipped
	s.at++
	return s.step()
}

// The two rows of a question. The NUL prefix cannot collide with anything a
// tree names.
const (
	keyYes = "\x00yes"
	keyNo  = "\x00no"
)

func (s *runScreen) View(width, height int) string {
	var b strings.Builder
	b.WriteString(s.headline() + "\n\n")
	switch {
	case s.err != nil:
		return b.String() + renderFailure(s.err, width)
	case s.asking != nil:
		return b.String() + s.question(width, height-2)
	}
	return b.String() + s.list(width, height-2)
}

// headline is the run itself: what is happening, or what happened — and, either
// way, the clock on it. An installation is minutes of a list filling in with
// nothing to judge it against; how long it has been going is the one thing
// somebody watching it cannot work out for themselves, and how long it took is
// the same answer once it is over.
func (s *runScreen) headline() string {
	switch {
	case s.asking != nil:
		return accentBold.Render(glyphs.ask) + field(" ") + boldStyle.Render(s.steps[s.at].Label())
	case !s.done:
		return accentStyle.Render(spinFrame()) + field(" ") + boldStyle.Render(labelInstallingFor(clock(s.elapsed())))
	case s.err != nil:
		return failStyle.Render(glyphs.fail) + field(" ") + boldStyle.Render(labelFailed())
	}
	return accentBold.Render(glyphs.ok) + field(" ") + boldStyle.Render(labelSucceededIn(clock(s.took)))
}

// question is what a task asked, with the answers filled into it, and the
// two ways to answer under it.
func (s *runScreen) question(width, height int) string {
	text := paragraph(s.steps[s.at].Question(s.app.store.Get), width)
	used := strings.Count(text, "\n") + 3 // the text itself, and the blank line under it
	return text + "\n\n" + s.asking.View(width, height-used)
}

// list is every task with its mark: done, running, skipped, still to come.
// The whole run is on screen from the first frame, so what is left is never a
// surprise — and the window follows the cursor down for a run too long to fit.
func (s *runScreen) list(width, height int) string {
	if height < 1 {
		return ""
	}
	top := 0
	if s.at >= height {
		top = min(s.at-height+1, len(s.steps)-height)
	}
	var b strings.Builder
	for i := top; i < min(top+height, len(s.steps)); i++ {
		if i > top {
			b.WriteByte('\n')
		}
		b.WriteString(s.line(i, width))
	}
	return b.String()
}

func (s *runScreen) line(i, width int) string {
	title := truncate(s.steps[i].Label(), width-markW)
	switch {
	case s.state[i] == ran:
		return accentStyle.Render(glyphs.ok) + field(" ") + softStyle.Render(title)
	case s.state[i] == skipped:
		return mutedStyle.Render(glyphs.skip) + field(" ") + mutedStyle.Render(title)
	case i == s.at && !s.done:
		return accentStyle.Render(spinFrame()) + field(" ") + boldStyle.Render(title)
	}
	// Still to come: no mark at all, so the column reads as a checklist filling
	// in from the top rather than as a row of empty boxes.
	return field(glyphBlank) + mutedStyle.Render(title)
}

// markW is what the mark column costs a title: the glyph and the space after it.
const markW = 2

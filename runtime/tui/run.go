package tui

import (
	"fmt"
	"strings"
	"time"

	"github.com/murkl/arch-os/runtime/internal/exec"
	"github.com/murkl/arch-os/runtime/internal/logging"
	"github.com/murkl/arch-os/runtime/internal/spec"

	tea "github.com/charmbracelet/bubbletea"
)

// runScreen runs the tasks, one after another, and shows how far it has got. It
// is the installation, from the first partition to whatever the module offers
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
// a module offers something rather than does it — reboot now, unmount, drop into
// the new system — without any of them being a page of their own.
type runScreen struct {
	app *app

	// name is what this run is called, where the module gave it a name: its own
	// `run:`, which is what the headline and the log are read in. Empty for a
	// module that named none, which the runtime can only call an installation.
	name string

	steps []*spec.Task
	state []mark

	// Where the two outcomes lead. Both are given by whoever started the run,
	// because only they know what a success means next and where a failure is
	// fixed — an installation that fails belongs back among the answers.
	then func() tea.Cmd
	back func() tea.Cmd

	at      int   // the task running now, or len(steps) once they all have
	stage   phase // how far the one at the cursor has got through what it declared
	ask     *ask
	asking  *picker
	told    *report
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

// phase is how far the task at the cursor has got through what it declared
// about itself: a value it has to ask for, then the offer, then the work, then
// whatever it has to report of what the work came to. Each is skipped by a task
// that declared none, and the order is the useful one — an offer can name what
// was just chosen, and a report can name what the work produced.
type phase int

const (
	phaseAsk phase = iota
	phaseConfirm
	phaseRun
	phaseReport
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

func newRun(a *app, name string, steps []*spec.Task, then, back func() tea.Cmd) *runScreen {
	return &runScreen{app: a, name: name, steps: steps, state: make([]mark, len(steps)), then: then, back: back}
}

// title is what this run is called in the log, which is the one place a name
// has to stand on its own.
func (s *runScreen) title() string {
	if s.name == "" {
		return labelInstalling()
	}
	return s.name
}

func (s *runScreen) Title() string { return "" }

// crumbRoot: a run is not a place you navigated to, it is a thing happening.
// The trail of pages that led here — a confirmation, a password — is spent, and
// leaving it standing would be a line of the frame saying where you no longer
// are. Titling itself nothing then leaves the row to the list.
func (s *runScreen) crumbRoot() bool { return true }

// working is what puts the turning mark in the header: something is running,
// which a question waiting for an answer is not, and neither is a page being
// read. Fetching the answers to one still is — that is a command of the module's,
// running like any other.
func (s *runScreen) working() bool {
	switch {
	case s.done, s.told != nil:
		return false
	case s.ask != nil:
		return s.ask.loading
	}
	return s.asking == nil
}

// holds: nothing in a run has a page behind it. The work cannot be stepped out
// of, and neither can a question it stopped to ask — the task that needs the
// answer has already started. So esc and backspace mean here what ctrl+c means
// everywhere, and the model turns them into the way out. What is left of a run
// once it is over is a page like any other, and is closed like one.
func (s *runScreen) holds() bool { return !s.done && s.told == nil }

// takesText: the narrowing box over a question the run stopped for. It has the
// first claim on esc — the box is closed before the question is left — and
// while it is open a letter is a character being typed.
func (s *runScreen) takesText() bool { return s.ask != nil && s.ask.filter.active() }

// status is the counter beside it: which step of how many. A run stopped on
// something it has to report is not counting: what that page says is that a
// thing is finished, and a number beside it saying how much is left would take
// it straight back.
func (s *runScreen) status() string {
	if s.done || s.told != nil {
		return ""
	}
	return labelCounter(min(s.at+1, len(s.steps)), len(s.steps))
}

func (s *runScreen) Hint() string {
	switch {
	case s.ask != nil:
		return s.ask.Hint()
	case s.asking != nil:
		return labelHintAnswer()
	case !s.settled:
		return labelHintRunning()
	case s.told != nil:
		return s.told.Hint()
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

// step takes on the task at the cursor: asks it whatever it said it needed,
// offers it if it is an offer, runs it, and ends the run when there are none
// left. It is called again after each of those, and carries on from where the
// phase says it got to.
//
// Each is started from here rather than from a loop, so the frame is redrawn
// between them and the list is always showing the truth.
func (s *runScreen) step() tea.Cmd {
	if s.at >= len(s.steps) {
		return s.finish(nil)
	}
	e := s.steps[s.at]
	if s.stage == phaseAsk {
		s.stage = phaseConfirm
		if e.Asks != "" {
			if !s.app.forced {
				s.ask = newAsk(s.app.module.Var(e.Asks))
				return tea.Batch(s.ask.Init(s.app), s.settle())
			}
			// Where nobody is watching there is nothing to put the question to,
			// so the answer is whatever the answer file already holds — and one
			// that is not there ends the run rather than reaching a script as an
			// empty string.
			if s.app.store.Get(e.Asks) == "" {
				return s.finish(fmt.Errorf("%s", labelNoAnswerFor(e.Asks)))
			}
		}
	}
	if s.stage == phaseConfirm {
		s.stage = phaseRun
		if e.Confirms() {
			// An offer nobody is there to take is answered by the one it opens
			// on. That is what a default is: what this task is when nothing
			// else is said about it.
			if s.app.forced {
				if e.Declines() {
					logging.Info("%s: declined", e.Name)
					s.state[s.at] = skipped
					return s.advance()
				}
				return s.start()
			}
			s.asking = newPicker([]item{
				{title: labelYes(), key: keyYes},
				{title: labelNo(), key: keyNo},
			})
			if e.Declines() {
				s.asking.focus(keyNo)
			}
			return s.settle()
		}
	}
	if s.stage == phaseReport {
		return s.tell(e)
	}
	return s.start()
}

// tell puts up what a task had to report of what it just did, and holds the run
// there until it has been read.
//
// The answer file is read back first, because a task that has something to show
// is a task that wrote it down: the value the page draws as a code is an answer
// like any other, and this is the moment it arrives. A task with nothing to
// report — which is nearly all of them — passes straight through.
func (s *runScreen) tell(e *spec.Task) tea.Cmd {
	if !e.Reports() {
		return s.advance()
	}
	if err := s.app.runner.Imported(); err != nil {
		logging.Warn("%s: %s", e.Name, err)
	}
	headline, body := e.ReportText(s.app.store.Get)
	// Read back either way — what a task wrote down is an answer like any
	// other — but only held on where somebody is there to read it.
	if s.app.forced {
		logging.Info("%s", headline)
		return tea.Batch(s.app.save(), s.advance())
	}
	s.told = newReport(headline, body, s.app.store.Get(e.Shows))
	return tea.Batch(s.app.save(), s.settle())
}

// advance moves the cursor to the next task, which starts over at the first
// phase — the one after it has its own questions to be asked.
func (s *runScreen) advance() tea.Cmd {
	s.at++
	s.stage = phaseAsk
	return s.step()
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
	s.done, s.err, s.session, s.asking, s.ask = true, err, nil, nil, nil
	if err != nil {
		logging.Error("%s", err)
	} else {
		logging.Info("%s: ok", s.title())
	}
	// Whatever a run was given is gone the moment it is over, whether it worked
	// or not: a failed installation is one that gets looked at, and nothing
	// typed in confidence should still be in memory while that happens.
	s.app.store.Forget()
	// A run nobody is watching ends the program rather than a page: the result
	// is an exit status and a log, and there is no one here to press a key.
	if s.app.forced {
		s.app.failure = err
		return quit()
	}
	return s.settle()
}

// settle starts the clock that makes what is on screen answerable.
func (s *runScreen) settle() tea.Cmd {
	s.settled = false
	return tea.Tick(settleFor, func(time.Time) tea.Msg { return settleMsg{} })
}

// stop kills the task that is running, and everything it started. Reached only
// once somebody has chosen a row on the way out — asking to leave a run does
// not stop it, saying so does.
func (s *runScreen) stop() {
	if s.session == nil {
		return
	}
	logging.Warn("%s: stopped", s.title())
	s.session.Kill()
	// Let go of it, so a second way out asking the same thing of this page says
	// so once. Whoever is waiting on the run holds its own reference.
	s.session = nil
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
		s.stage = phaseReport
		return s, s.step()

	case askedMsg:
		if err := s.ask.fill(msg, s.app.store.Get(s.ask.v.Name)); err != nil {
			return s, s.finish(err)
		}
		return s, nil

	case settleMsg:
		s.settled = true
		return s, nil

	case tea.KeyMsg:
		// The keys that ask to leave never reach this page — the model takes
		// them, and asking is not stopping: the page it opens is drawn over
		// this one and the run carries on behind it. See holds and leave.go.
		if !s.settled {
			// Killing a half-finished package transaction is worse than waiting
			// for it, so nothing else means anything while a task runs, and
			// nothing at all for a moment after a question or a result appears.
			return s, nil
		}
		if s.ask != nil {
			return s, s.answerAsk(msg)
		}
		if s.asking != nil {
			return s, s.answer(msg)
		}
		// A page that only had to be read is closed the way the result of a run
		// is: deliberately, with enter or esc, and by nothing else.
		if s.told != nil {
			if answers(msg) {
				s.told = nil
				return s, s.advance()
			}
			return s, nil
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

// answerAsk takes the value a task asked for and carries on into whatever else
// that task declared. There is no way past the question but answering it: the
// work it belongs to has already started, and esc has nothing behind it to go
// back to.
func (s *runScreen) answerAsk(key tea.KeyMsg) tea.Cmd {
	cmd, given := s.ask.Update(key, s.app)
	if !given {
		return cmd
	}
	logging.Info("%s: %s", s.ask.v.Name, s.app.store.Get(s.ask.v.Name))
	s.ask = nil
	return tea.Batch(cmd, s.step())
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
	return s.advance()
}

// The two rows of a question. The NUL prefix cannot collide with anything a
// module names.
const (
	keyYes = "\x00yes"
	keyNo  = "\x00no"
)

func (s *runScreen) View(width, height int) string {
	// A report is the whole page. The line that says what is running is what it
	// is standing in for: the run has stopped, and there is nothing above the
	// mark it draws for that line to be about.
	if s.told != nil {
		return s.told.View(width, height)
	}
	var b strings.Builder
	b.WriteString(s.headline() + "\n\n")
	switch {
	case s.err != nil:
		return b.String() + renderFailure(s.err, width)
	case s.ask != nil:
		return b.String() + s.ask.View(width, height-2)
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
	// A task that has stopped the run to ask something is named in place of the
	// run itself: what is on screen is that one question, and the clock has
	// nothing to do with how long somebody takes to answer it.
	switch {
	case s.asking != nil, s.ask != nil && !s.ask.loading:
		return accentBold.Render(glyphs.ask) + field(" ") + boldStyle.Render(s.steps[s.at].Label())
	case !s.done:
		return accentStyle.Render(spinFrame()) + field(" ") + boldStyle.Render(s.running())
	case s.err != nil:
		return failStyle.Render(glyphs.fail) + field(" ") + boldStyle.Render(s.failed())
	}
	return accentBold.Render(glyphs.ok) + field(" ") + boldStyle.Render(s.succeeded())
}

// The three things a run says about itself, each in the module's own name for it
// where there is one and in the only name the runtime has where there is not.
func (s *runScreen) running() string {
	if s.name == "" {
		return labelInstallingFor(clock(s.elapsed()))
	}
	return labelRunningFor(s.name, clock(s.elapsed()))
}

func (s *runScreen) succeeded() string {
	if s.name == "" {
		return labelSucceededIn(clock(s.took))
	}
	return labelRunDone(s.name, clock(s.took))
}

func (s *runScreen) failed() string {
	if s.name == "" {
		return labelFailed()
	}
	return labelRunFailed(s.name)
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

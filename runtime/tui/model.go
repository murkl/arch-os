package tui

import (
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// Model owns the terminal, the screen stack and the chrome around whatever is
// on top of it. A screen never draws its own frame, so there is exactly one
// place that decides what the program looks like — and exactly one place that
// can promise nothing ever escapes it.
type Model struct {
	app    *app
	stack  []screen
	width  int
	height int

	// The opening. splash is the logo while it is up and nil once it has gone;
	// arrived is how far the interface is into coming up behind it.
	splash  *splashModel
	arrived time.Duration

	// spinning guards the clock against a second chain being started while one
	// is already running; which frame the working mark is on comes from
	// spinFrame, off the wall clock, so two marks on screen at once turn
	// together.
	spinning bool

	status    string
	statusBad bool
	quitting  bool
}

// A terminal that has not reported its size yet still has to render something,
// and 80x24 is the size every terminal is at least.
const (
	defaultWidth  = 80
	defaultHeight = 24
)

// statuser is a screen with something to say in the header — the stage counter
// during an install. Optional, like every other screen extra.
type statuser interface{ status() string }

func newModel(a *app, logo string) *Model {
	m := &Model{app: a, width: defaultWidth, height: defaultHeight}
	m.stack = []screen{a.start()}
	if logo == "" {
		// Nothing to come up out of: the interface is simply there.
		m.arrived = fadeFor
		return m
	}
	m.splash = newSplash(logo, a.version)
	return m
}

func (m *Model) Init() tea.Cmd {
	cmd := tea.Batch(initOf(m.top()), m.turn())
	if m.splash == nil {
		return cmd
	}
	return tea.Batch(cmd, animTick())
}

func (m *Model) top() screen { return m.stack[len(m.stack)-1] }

// turn keeps the working mark moving, and keeps exactly one chain of ticks
// doing it — a second would turn the mark at twice the rate and outlive the
// work it stands for. It answers nil once there is nothing left to say, which
// is what stops the clock.
func (m *Model) turn() tea.Cmd {
	if m.spinning || !working(m.top()) {
		return nil
	}
	m.spinning = true
	return spinTick()
}

// spinMsg is one turn of the working mark. Its own clock rather than the
// opening's: that one is a fixed animation with an end, this one runs for as
// long as something is happening and has to be startable again afterwards.
type spinMsg struct{}

func spinTick() tea.Cmd {
	return tea.Tick(spinEvery, func(time.Time) tea.Msg { return spinMsg{} })
}

// animate runs the one clock the opening has: the light going round and the
// logo dimming out, then the interface rising out of the background it left.
// It stops asking for frames the moment nothing is moving any more.
func (m *Model) animate() tea.Cmd {
	if m.splash != nil {
		if done := m.splash.advance(); !done {
			setFade(m.splash.light())
			return animTick()
		}
		m.splash = nil
	}
	if m.arrived >= fadeFor {
		setFade(1)
		return nil
	}
	m.arrived += animEvery
	setFade(float64(m.arrived) / float64(fadeFor))
	return animTick()
}

func (m *Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		// A zero-size report happens and would collapse the layout for good.
		if msg.Width > 0 && msg.Height > 0 {
			m.width, m.height = msg.Width, msg.Height
		}
		return m, nil

	case animMsg:
		return m, m.animate()

	case spinMsg:
		m.spinning = false
		return m, m.turn()

	case tea.KeyMsg:
		// ctrl+c always leaves, whatever a screen would otherwise do with it.
		// It is the one way out of a running installation, and it has to be
		// meant: no other key can be pressed by accident into that gap.
		if msg.String() == "ctrl+c" {
			return m, m.exit()
		}
		// The splash answers to one thing only, and swallows the key that says
		// it — otherwise dismissing the logo would also press whatever the page
		// underneath has under the cursor. Arrows are excepted: they are what
		// this terminal makes of a mouse wheel, and are nobody saying anything.
		if m.splash != nil {
			if !scrolls(msg) {
				m.splash.skip()
			}
			return m, nil
		}
		m.status = "" // any keystroke clears a flash

	case pushScreenMsg:
		m.stack = append(m.stack, msg.s)
		// A page that runs something starts it in its own Init, so the clock for
		// the mark has to be offered again here: it stopped when the last thing
		// finished, and nothing else would wake it.
		return m, tea.Batch(initOf(msg.s), m.turn())

	case popScreenMsg:
		n := max(msg.n, 1)
		if n >= len(m.stack) {
			// Backing off the last page there is. Nothing is behind it, so this
			// is the same thing as asking to leave.
			return m, m.exit()
		}
		m.stack = m.stack[:len(m.stack)-n]
		if r, ok := m.top().(refresher); ok {
			r.Refresh()
		}
		return m, tea.Batch(initOf(m.top()), m.turn())

	case resetStackMsg:
		m.stack = []screen{msg.s}
		return m, tea.Batch(initOf(msg.s), m.turn())

	case flashMsg:
		m.status, m.statusBad = msg.text, msg.bad
		return m, nil

	case leaveMsg:
		return m, m.exit()

	case quitMsg:
		return m, m.stopAndQuit()
	}

	next, cmd := m.top().Update(msg)
	m.stack[len(m.stack)-1] = next
	return m, tea.Batch(cmd, m.turn())
}

func (m *Model) View() string {
	// An empty view on the way out hands the terminal back clean, without the
	// last frame left painted on it.
	if m.quitting {
		return ""
	}
	if m.splash != nil {
		return m.splash.View(m.width, m.height)
	}
	w, h := frameSize(m.width, m.height)

	trail := crumbFrom(m.stack)
	crumbs := make([]string, 0, len(trail))
	for _, s := range trail {
		if t := s.Title(); t != "" {
			crumbs = append(crumbs, t)
		}
	}

	// A flash stands where the page's own status usually is, and how it is inked
	// says which of the two it is: what went wrong reads as a failure, what
	// merely happened reads like the status it replaced.
	status, alarm := m.pageStatus(), false
	if m.status != "" {
		status, alarm = m.status, m.statusBad
	}

	return renderFrame(m.width, m.height, chrome{
		brand:   m.app.spec.Name(),
		status:  status,
		alarm:   alarm,
		mark:    m.indicator(),
		crumb:   breadcrumb(crumbs, w),
		body:    m.top().View(w, h-headerRows(len(crumbs))),
		hint:    m.top().Hint(),
		version: m.app.version,
	})
}

// exit is what every way out of the interface goes through — ctrl+c, the row
// that says quit, backing off the last page, the end of an installation.
//
// Where the tree said how this machine is put down, that is a question rather
// than an exit: the machine booted to run the installer and there is nothing
// behind it to quit into, so the page offering a restart or a shutdown is what
// happens next. Where it said nothing, the program ends, which is right for an
// installer somebody started from a shell they are still sitting in.
//
// Whatever the page on top was running is stopped first, either way: leaving a
// package transaction writing to a disk nobody is watching any more is worse
// than an interrupted one. A run stopped like that is over, so the page that
// asks is put in its place rather than on top of it — there is nothing behind it
// to go back to.
func (m *Model) exit() tea.Cmd {
	if !m.app.spec.Leaves() {
		return m.stopAndQuit()
	}
	if _, asking := m.top().(*leaveScreen); asking {
		return nil
	}
	running := working(m.top())
	stop(m.top())
	if running {
		return reset(newLeave(m.app))
	}
	return push(newLeave(m.app))
}

// stopAndQuit ends the program, after telling the page on top to put down
// whatever it is holding — so a run can never outlive the interface that
// started it.
func (m *Model) stopAndQuit() tea.Cmd {
	stop(m.top())
	m.quitting = true
	return tea.Quit
}

// pageStatus is whatever the current page has to say about itself in the
// header, which for most pages is nothing.
func (m *Model) pageStatus() string {
	if s, ok := m.top().(statuser); ok {
		return s.status()
	}
	return ""
}

// indicator is the working mark: the spinner while anything at all is running,
// and nothing otherwise. One slot, one meaning.
func (m *Model) indicator() string {
	if working(m.top()) {
		return accentStyle.Render(spinFrame())
	}
	return ""
}

// headerRows is how much of the frame the chrome takes, so a screen is told the
// height it actually has.
func headerRows(crumbs int) int {
	rows := 4 // brand, rule, rule, footer
	if crumbs > 0 {
		rows += 2 // breadcrumb and the blank line under it
	}
	return rows
}

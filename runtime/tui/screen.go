package tui

import tea "github.com/charmbracelet/bubbletea"

// A screen is a page of the interface. The contract is four methods, and the
// smallness is the point: a screen says what it is called, what it does with a
// key, what it looks like in the space it is given, and which keys it answers
// to. Everything else — the frame, the breadcrumb, the footer — belongs to the
// model and no screen can disagree with it.
//
// Screens are a stack, one in front of the last, bar one: the way out is drawn
// over the stack rather than on it, because it is a question about what is
// happening rather than a step further into it. See Model.leaving.
type screen interface {
	// Title is this screen's segment of the breadcrumb. Empty adds nothing.
	Title() string
	Update(tea.Msg) (screen, tea.Cmd)
	// View is handed its space rather than reading a global, so a screen can be
	// rendered at any size — which is what makes it testable.
	View(width, height int) string
	// Hint is the footer's key help, kept next to the keys it describes so the
	// two cannot drift apart.
	Hint() string
}

// Optional, found by type assertion rather than declared: a screen that needs
// to start work implements Init, one that reads the system afresh on the way
// back implements Refresh, one with something running implements worker.
type (
	initer    interface{ Init() tea.Cmd }
	refresher interface{ Refresh() }
	worker    interface{ working() bool }

	// A screen with something running that must not outlive the program.
	stopper interface{ stop() }

	// A screen that starts the breadcrumb over at itself rather than adding to
	// the trail behind it. One run of questions is not a path through the
	// program — it is one place you stay in while the question changes, and a
	// trail of every answer already given would be a line that grows across the
	// frame saying nothing about where you are.
	crumbRooter interface{ crumbRoot() bool }

	// A screen that names the heading it stands under. For a page that begins
	// the trail and is still not the whole of where you are: the opening is a
	// row of pages one after another, and each of them is somewhere inside it.
	crumbHeader interface{ crumbHead() string }
)

// opening is embedded by the pages in front of the questions proper: the
// language, the fork, what a module asks first, the network, the check, the
// starting points. They follow one another rather than lead into one another,
// so each stands under one heading instead of inside the page before it — a
// line growing by a segment for every page already answered says where somebody
// has been, which is not what a breadcrumb is for.
type opening struct{}

func (opening) crumbRoot() bool   { return true }
func (opening) crumbHead() string { return labelOpening() }

// working reports whether s has something running, defaulting to no: most
// screens are a list waiting for a key.
func working(s screen) bool {
	w, ok := s.(worker)
	return ok && w.working()
}

// crumbFrom is where the breadcrumb starts: the last screen on the stack that
// stands for itself, or the bottom of the stack when none does.
func crumbFrom(stack []screen) []screen {
	for i := len(stack) - 1; i >= 0; i-- {
		if r, ok := stack[i].(crumbRooter); ok && r.crumbRoot() {
			return stack[i:]
		}
	}
	return stack
}

// crumbTrail is what the breadcrumb says: the heading the page stands under,
// where it names one, and then the title of every screen from there up.
func crumbTrail(stack []screen) []string {
	trail := crumbFrom(stack)
	out := make([]string, 0, len(trail)+1)
	if len(trail) > 0 {
		if h, ok := trail[0].(crumbHeader); ok && h.crumbHead() != "" {
			out = append(out, h.crumbHead())
		}
	}
	for _, s := range trail {
		if t := s.Title(); t != "" {
			out = append(out, t)
		}
	}
	return out
}

// stop tells a screen to put down whatever it is holding, on the way out.
func stop(s screen) {
	if w, ok := s.(stopper); ok {
		w.stop()
	}
}

func initOf(s screen) tea.Cmd {
	if i, ok := s.(initer); ok {
		return i.Init()
	}
	return nil
}

// How a screen changes what is on the stack. A screen returns one of these as a
// command rather than manipulating the stack, so the stack has exactly one
// owner.
type (
	pushScreenMsg struct{ s screen }
	popScreenMsg  struct{ n int }
	resetStackMsg struct{ s screen }
	flashMsg      struct {
		text string
		bad  bool
	}

	// The two ways this program ends, and they are not the same thing. leaveMsg
	// is a page saying it has nothing after it: what happens then is the model's
	// to decide, and on a machine that booted to run this it is a question
	// rather than an exit — see Model.exit. quitMsg is the program actually
	// stopping, which only the two things that know the machine is already going
	// down ever say: the page that just restarted it, and a task the program
	// does not come back from.
	leaveMsg struct{}
	quitMsg  struct{}

	// dismissMsg closes the way out again, leaving whatever is behind it
	// exactly as it was — including a run that never stopped.
	dismissMsg struct{}
)

func push(s screen) tea.Cmd  { return func() tea.Msg { return pushScreenMsg{s} } }
func pop() tea.Cmd           { return func() tea.Msg { return popScreenMsg{n: 1} } }
func reset(s screen) tea.Cmd { return func() tea.Msg { return resetStackMsg{s} } }
func leave() tea.Cmd         { return func() tea.Msg { return leaveMsg{} } }
func dismiss() tea.Cmd       { return func() tea.Msg { return dismissMsg{} } }
func quit() tea.Cmd          { return func() tea.Msg { return quitMsg{} } }

func flashBad(text string) tea.Cmd {
	return func() tea.Msg { return flashMsg{text: text, bad: true} }
}

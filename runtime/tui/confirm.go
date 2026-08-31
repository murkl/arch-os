package tui

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

// confirmScreen is the last page before anything is changed.
//
// What it says comes entirely from the tree, with the answers filled into it,
// because only the tree knows what is about to happen — which disk, whether
// it is erased or shared, what that costs. The runtime supplies the moment, not
// the warning.
//
// It answers to enter and nothing else. Every other key, and every scroll — a
// wheel arrives here as an arrow — leaves the page exactly where it is.
type confirmScreen struct {
	app *app
}

func newConfirm(a *app) *confirmScreen { return &confirmScreen{app: a} }

func (s *confirmScreen) Title() string {
	if name := s.app.mode().Label(); name != "" {
		return name
	}
	return labelInstall()
}

func (s *confirmScreen) Hint() string { return labelHintStart() }

func (s *confirmScreen) Update(msg tea.Msg) (screen, tea.Cmd) {
	key, ok := msg.(tea.KeyMsg)
	if !ok {
		return s, nil
	}
	switch {
	case confirms(key):
		return s, push(startInstall(s.app, 0))
	case backs(key):
		return s, pop()
	}
	return s, nil
}

func (s *confirmScreen) View(width, height int) string {
	// Named after what is about to happen where the tree has a name for it, and
	// after the only thing an installer does where it has not.
	ready, start := labelReady(), labelStartInstall()
	if name := s.app.mode().Label(); name != "" {
		ready, start = labelReadyToStart(), labelStartNamed(name)
	}
	var b strings.Builder
	b.WriteString(alertStyle.Render(ready) + "\n\n")
	if text := s.app.mode().ConfirmText(s.app.store.Get); text != "" {
		b.WriteString(paragraph(text, width) + "\n")
	}
	return b.String() + "\n" + accentBold.Render(glyphs.cursor+start)
}

// startInstall is the way into an installation: the secrets that have to be
// typed first, in order, and the run itself once there are none left.
//
// Asked here rather than among the other questions, because a secret is never
// written down: it would be missing again at every start, and no machine could
// ever be finished answering. Here it is typed once, used, and forgotten.
func startInstall(a *app, next int) screen {
	secrets := a.store.Secrets()
	if next < len(secrets) {
		return newSecret(a, secrets[next], func() tea.Cmd {
			return push(startInstall(a, next+1))
		})
	}
	// Nothing follows a finished run: everything the tree had to offer once the
	// system was installed was a task of the last stage and has been offered.
	// Enter on the result leaves. A failed one lands back on the hub, which is
	// where a wrong answer is corrected.
	return newRun(a, a.mode().Label(), a.runner.Tasks(),
		leave,
		func() tea.Cmd { return reset(newHub(a)) })
}

package tui

import (
	"strings"

	"installer/internal/wlan"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// networkScreen stands between the opening and everything else: every stage
// past it downloads something, so it checks for internet and, if there is
// none, offers the one fix a machine in front of you usually needs — a
// wireless network.
//
// It is not a wall. Carrying on without a connection is a normal thing to do
// here — the tree's own preflight check runs right after this one and refuses
// properly if it still matters.
type networkScreen struct {
	app   *app
	radio *wlan.Radio

	step  netStep
	list  *picker
	input textinput.Model

	dev  string
	ssid string
	busy string
	err  string
}

type netStep int

const (
	netChecking netStep = iota
	netScanning
	netChoosing
	netPassphrase
	netJoining
	netOffline // nothing to offer, or the user backed out of the list
)

func newNetwork(a *app, r *wlan.Radio) *networkScreen {
	return &networkScreen{app: a, radio: r}
}

func (s *networkScreen) Title() string { return s.radio.Title() }

// working is what puts the turning mark in the header while a check, a scan
// or a join is in flight.
func (s *networkScreen) working() bool {
	switch s.step {
	case netChecking, netScanning, netJoining:
		return true
	}
	return false
}

type (
	netOnlineMsg  struct{ ok bool }
	netScannedMsg struct {
		device string
		names  []string
		err    error
	}
	netJoinedMsg struct{ err error }
)

func (s *networkScreen) Init() tea.Cmd {
	s.step, s.busy = netChecking, labelNetworkChecking()
	r := s.radio
	return func() tea.Msg { return netOnlineMsg{ok: r.Online()} }
}

func (s *networkScreen) Update(msg tea.Msg) (screen, tea.Cmd) {
	switch msg := msg.(type) {

	case netOnlineMsg:
		if msg.ok {
			return s, reset(s.app.afterNetwork())
		}
		// Offline, and nothing declared to fix it with: say so and move on
		// rather than pretending there is a choice.
		if !s.radio.Joinable() {
			s.step = netOffline
			return s, nil
		}
		return s, s.scan()

	case netScannedMsg:
		if msg.err != nil {
			s.step, s.err = netOffline, msg.err.Error()
			return s, nil
		}
		if len(msg.names) == 0 {
			s.step, s.err = netOffline, labelNetworkNoNetworks()
			return s, nil
		}
		s.dev = msg.device
		items := make([]item, len(msg.names))
		for i, n := range msg.names {
			items[i] = item{title: n, key: n}
		}
		s.list = newPicker(items)
		s.step, s.err = netChoosing, ""
		return s, nil

	case netJoinedMsg:
		if msg.err != nil {
			// Almost always the passphrase. Back to the list rather than out of
			// the screen: the next thing to try is another go at it.
			s.step, s.err = netChoosing, msg.err.Error()
			return s, nil
		}
		return s, reset(s.app.afterNetwork())

	case tea.KeyMsg:
		return s, s.key(msg)
	}
	return s, nil
}

func (s *networkScreen) key(k tea.KeyMsg) tea.Cmd {
	switch s.step {

	case netChoosing:
		switch {
		case confirms(k):
			ssid, ok := s.list.chosen()
			if !ok {
				return nil
			}
			s.ssid, s.step, s.err = ssid, netPassphrase, ""
			s.input = textinput.New()
			s.input.EchoMode = textinput.EchoPassword
			s.input.EchoCharacter = []rune(glyphs.secret)[0]
			s.input.CharLimit = 128
			styleInput(&s.input)
			s.input.Focus()
			return textinput.Blink
		case cancels(k):
			s.step = netOffline
			return nil
		case k.String() == "r":
			return s.scan()
		}
		s.list.Update(k)
		return nil

	case netPassphrase:
		switch {
		case confirms(k):
			s.step, s.busy = netJoining, labelNetworkJoining(s.ssid)
			r, dev, ssid, pass := s.radio, s.dev, s.ssid, s.input.Value()
			return func() tea.Msg { return netJoinedMsg{err: r.Join(dev, ssid, pass)} }
		case cancels(k):
			s.step, s.err = netChoosing, ""
			return nil
		}
		var cmd tea.Cmd
		s.input, cmd = s.input.Update(k)
		return cmd

	case netOffline:
		switch {
		case confirms(k):
			// Carry on without. The tree's preflight check runs next and
			// refuses properly if it still matters.
			return reset(s.app.afterNetwork())
		case k.String() == "r":
			return s.Init()
		}
	}
	return nil
}

func (s *networkScreen) scan() tea.Cmd {
	s.step, s.busy, s.err = netScanning, labelNetworkScanning(), ""
	r := s.radio
	return func() tea.Msg {
		dev, err := r.Interface()
		if err != nil {
			return netScannedMsg{err: err}
		}
		names, err := r.Networks(dev)
		return netScannedMsg{device: dev, names: names, err: err}
	}
}

func (s *networkScreen) View(width, height int) string {
	switch s.step {
	case netChecking, netScanning, netJoining:
		return accentStyle.Render(spinFrame()) + field(" ") + boldStyle.Render(s.busy)

	case netChoosing:
		var b strings.Builder
		if help := s.radio.Description(); help != "" {
			head := paragraph(help, width) + "\n\n"
			height -= strings.Count(head, "\n")
			b.WriteString(head)
		}
		errRows := 0
		if s.err != "" {
			errRows = 2
		}
		b.WriteString(s.list.View(width, height-errRows))
		if s.err != "" {
			b.WriteString("\n\n" + failStyle.Render(truncate(s.err, width)))
		}
		return b.String()

	case netPassphrase:
		s.input.Width = width - lipgloss.Width(glyphs.cursor) - 1
		var b strings.Builder
		b.WriteString(boldStyle.Render(s.ssid) + "\n")
		b.WriteString(softStyle.Render(labelPassphrase()) + "\n")
		b.WriteString(cursorStyle.Render(glyphs.cursor) + s.input.View())
		return b.String()
	}

	// netOffline
	body := labelNetworkOffline()
	if s.err != "" {
		body = s.err
	}
	help := labelNetworkOfflineHelp()
	if !s.radio.Joinable() {
		help = labelNetworkOfflineHelpUnjoinable()
	}
	var b strings.Builder
	b.WriteString(failStyle.Render(glyphs.fail) + field(" ") + boldStyle.Render(body) + "\n\n")
	b.WriteString(paragraph(help, width) + "\n\n")
	b.WriteString(accentBold.Render(glyphs.cursor + labelContinueAnyway()))
	return b.String()
}

func (s *networkScreen) Hint() string {
	switch s.step {
	case netChecking, netScanning, netJoining:
		return labelHintRunning()
	case netChoosing:
		return labelHintNetworkChoosing()
	case netPassphrase:
		return labelHintInput()
	}
	return labelHintNetworkOffline()
}

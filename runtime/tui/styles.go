package tui

import (
	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/lipgloss"
)

// Every style is built here and nowhere else, so a screen renders content and
// never decides how it looks. That is the whole reason the interface reads as
// one thing rather than as a dozen — and the reason it can be faded in as one
// thing too.
var (
	// baseStyle is the one field the whole interface sits on: the splash, the
	// frame's interior, and the page around it. Every other style here is
	// built on this, so painting the field once paints everything.
	baseStyle   lipgloss.Style
	accentStyle lipgloss.Style
	accentBold  lipgloss.Style
	frameStyle  lipgloss.Style
	cursorStyle lipgloss.Style
	textStyle   lipgloss.Style
	boldStyle   lipgloss.Style
	softStyle   lipgloss.Style
	mutedStyle  lipgloss.Style
	headStyle   lipgloss.Style
	infoStyle   lipgloss.Style
	goodStyle   lipgloss.Style
	failStyle   lipgloss.Style
	alertStyle  lipgloss.Style
	ruleStyle   lipgloss.Style
	dimStyle    lipgloss.Style
)

// buildStyles reads the palette at whatever level it is currently showing, so
// every style here comes out faded by the same amount.
func buildStyles() {
	baseStyle = lipgloss.NewStyle()

	accentStyle = baseStyle.Foreground(fade(colors.accent))
	accentBold = accentStyle.Bold(true)
	cursorStyle = accentStyle.Bold(true)

	// Body text is the terminal's own foreground: no colour set at all, so it
	// follows whatever theme the terminal is wearing without this program being
	// told about it. It is the one choice not worth making — every other colour
	// here carries a meaning, and ink that is merely ink carries none.
	//
	// One thing takes that choice back. The opening fades the whole interface up
	// out of the background, and a colour the terminal keeps to itself cannot be
	// blended into anything — so the scheme's own ink stands in while that runs.
	var ink lipgloss.TerminalColor = lipgloss.NoColor{}
	if fadeLevel < 1 {
		ink = fade(colors.text)
	}
	textStyle = baseStyle.Foreground(ink)
	boldStyle = textStyle.Bold(true)
	softStyle = baseStyle.Foreground(fade(colors.soft))
	mutedStyle = baseStyle.Foreground(fade(colors.muted))
	headStyle = baseStyle.Foreground(fade(colors.head)).Bold(true)
	infoStyle = baseStyle.Foreground(fade(colors.info))
	goodStyle = baseStyle.Foreground(fade(colors.good)).Bold(true)
	failStyle = baseStyle.Foreground(fade(colors.fail))

	// The one loud style in the program, for the one moment that has to be
	// noticed: something is about to be done that needs a password. Bold *and*
	// the warning colour, because either alone reads as another heading.
	alertStyle = baseStyle.Foreground(fade(colors.warn)).Bold(true)

	ruleStyle = baseStyle.Foreground(fade(colors.sunk))

	// A row that cannot be chosen yet is dimmed rather than hidden: knowing an
	// entry exists and why it is out of reach beats it silently not being there.
	dimStyle = baseStyle.Foreground(fade(colors.muted))

	// NormalBorder, not RoundedBorder: the rounded corners are missing from
	// several monospace fonts and fall back to a box that does not line up.
	frameStyle = baseStyle.
		Border(lipgloss.NormalBorder()).
		BorderForeground(fade(colors.sunk)).
		Padding(padV, padH)
}

// field renders the cells that are not words: the gap between two columns, the
// blank in front of a row, the margin beside a value. One place for them, so
// that whatever the interface sits on is decided in exactly one file rather than
// wherever somebody happened to write a run of spaces.
func field(s string) string { return baseStyle.Render(s) }

// placeOnField centres a block in the terminal, leaving what is around it as the
// terminal's own.
func placeOnField(width, height int, block string) string {
	return lipgloss.Place(width, height, lipgloss.Center, lipgloss.Center, block)
}

// styleInput dresses a text box in the interface's own styles. bubbles'
// textinput sets its own otherwise, which would leave one patch of the frame
// unfaded during the opening and a stranger's grey placeholder in it afterwards.
// The cursor block takes cursorStyle, the same accent a list row's own cursor is
// drawn in, so the two read as one idea rather than two different cursors.
func styleInput(m *textinput.Model) {
	// No prompt of its own: every box in this program already has the same
	// cursor in front of it that a list row under the cursor has, and two
	// markers side by side would read as one of them meaning something.
	m.Prompt = ""
	m.PromptStyle = textStyle
	m.TextStyle = textStyle
	m.PlaceholderStyle = mutedStyle
	m.Cursor.Style = cursorStyle
	m.Cursor.TextStyle = textStyle
}

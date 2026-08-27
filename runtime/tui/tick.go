package tui

import (
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// pollEvery is how often a page with something running asks to be redrawn.
// Fast enough for the mark to look alive, slow enough that a long install does
// not spend its time painting frames.
const pollEvery = 100 * time.Millisecond

// tickMsg is one of those redraws. A page that has work in flight asks for the
// next one for as long as it has any, and stops asking the moment it does not —
// so an idle interface costs nothing at all.
type tickMsg struct{}

func tick() tea.Cmd {
	return tea.Tick(pollEvery, func(time.Time) tea.Msg { return tickMsg{} })
}

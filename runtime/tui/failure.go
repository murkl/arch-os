package tui

import (
	"strings"

	"installer/internal/exec"
	"installer/internal/logging"

	"github.com/charmbracelet/lipgloss"
)

// One failure, drawn one way, wherever it comes from — the system check that
// refused to start, or a stage that died halfway through. A person reading it
// is not having a good day, and the last thing they need is two different
// shapes of bad news to learn.
//
// The order is what somebody actually needs, in that order: what went wrong, in
// the words of the tool that said so; then where — which script, which line,
// which command, which exit code; then where the rest of it is written down.
// Nothing is folded away and nothing has to be pressed for.
func renderFailure(err error, width int) string {
	var b strings.Builder
	f, ok := err.(*exec.Failure)
	if !ok {
		b.WriteString(failStyle.Render(wrapped(err.Error(), width)))
		return b.String() + logNote(width)
	}

	if msg := strings.TrimSpace(f.Stderr); msg != "" {
		b.WriteString(failStyle.Render(wrapped(msg, width)))
		b.WriteString("\n\n")
	}
	// The label column is as wide as the widest label plus a gap, so the values
	// stand in one column — the same rule every other pair in this interface
	// lines up by.
	fields := f.Fields()
	labelW := 0
	for _, kv := range fields {
		labelW = max(labelW, len(kv[0]))
	}
	for _, kv := range fields {
		label := mutedStyle.Render(kv[0] + strings.Repeat(" ", labelW-len(kv[0])))
		b.WriteString(label + field(strings.Repeat(" ", gapM)) + softStyle.Render(truncate(kv[1], width-labelW-gapM)) + "\n")
	}
	return b.String() + logNote(width)
}

// logNote says where everything that did not fit is. It is the one place the
// interface admits there is more output than it showed — and it is a path, not
// an offer to show it: a page of somebody else's build log inside this frame
// would be the frame breaking.
func logNote(width int) string {
	path := logging.Path()
	if path == "" {
		return ""
	}
	// Broken across lines rather than cut short: this is the one thing on the
	// page that has to survive being read out to somebody else, and half a path
	// is worth nothing.
	return "\n" + mutedStyle.Render(strings.Join(hardWrap(labelLogHint(path), width), "\n"))
}

// hardWrap breaks a string at the width, on a space where there is one and
// mid-word where there is not — for the one line here that is a path rather
// than a sentence.
func hardWrap(s string, width int) []string {
	var out []string
	for _, line := range wrap(s, width) {
		for lipgloss.Width(line) > width {
			cut := []rune(line)[:width]
			out = append(out, string(cut))
			line = string([]rune(line)[width:])
		}
		out = append(out, line)
	}
	return out
}

// wrapped is body text at the reading width, joined back into one block.
func wrapped(s string, width int) string {
	return strings.Join(wrap(s, bodyWidth(width)), "\n")
}

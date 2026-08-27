package tui

import (
	"strings"
	"testing"
	"unicode"

	"github.com/charmbracelet/lipgloss"
)

// consoleFont is what a Linux virtual console can draw: the printable ASCII
// range, plus the handful of codepoints every console font inherits from
// codepage 437 and from the lat* tables built on it.
//
// Written out rather than read off the running machine on purpose. What matters
// is not which font this developer happens to have loaded — it is which
// codepoints are safe on the machine the ISO boots on, and that is a fact about
// console fonts rather than about anything here.
const consoleFont = "─│┌┐└┘├┤┬┴┼░▒█▄▀▌▐■·•»«›‹±°÷×↑↓←→▲▼"

func inConsoleFont(s string) bool {
	for _, r := range s {
		if r < unicode.MaxASCII && unicode.IsPrint(r) {
			continue
		}
		if !strings.ContainsRune(consoleFont, r) {
			return false
		}
	}
	return true
}

// The whole point of the reduced set: a console font holds at most 512 glyphs,
// and a codepoint that is not among them is not drawn as anything sensible —
// the kernel puts a replacement in its place, so a spinner stops turning and a
// tick turns into a letter.
func TestEveryPlainGlyphIsOneAConsoleFontHas(t *testing.T) {
	g := plainGlyphs
	marks := map[string]string{
		"cursor":      g.cursor,
		"crumb":       g.crumb,
		"rule":        g.rule,
		"dash":        g.dash,
		"scrollTrack": g.scrollTrack,
		"scrollThumb": g.scrollThumb,
		"ok":          g.ok,
		"fail":        g.fail,
		"ask":         g.ask,
		"skip":        g.skip,
		"add":         g.add,
		"secret":      g.secret,
	}
	for name, mark := range marks {
		if !inConsoleFont(mark) {
			t.Errorf("%s is %q, which no console font can draw", name, mark)
		}
	}
	for i, frame := range append(append([]string{}, g.focus...), g.spinner...) {
		if !inConsoleFont(frame) {
			t.Errorf("frame %d is %q, which no console font can draw", i, frame)
		}
	}
}

// The two sets have to be interchangeable, not merely both present: a mark that
// is suddenly two cells wide would push every title on the page out of its
// column.
func TestBothSetsAreTheSameShape(t *testing.T) {
	pairs := [][3]string{
		{"cursor", fullGlyphs.cursor, plainGlyphs.cursor},
		{"crumb", fullGlyphs.crumb, plainGlyphs.crumb},
		{"scrollTrack", fullGlyphs.scrollTrack, plainGlyphs.scrollTrack},
		{"scrollThumb", fullGlyphs.scrollThumb, plainGlyphs.scrollThumb},
		{"ok", fullGlyphs.ok, plainGlyphs.ok},
		{"fail", fullGlyphs.fail, plainGlyphs.fail},
		{"skip", fullGlyphs.skip, plainGlyphs.skip},
	}
	for _, p := range pairs {
		if lipgloss.Width(p[1]) != lipgloss.Width(p[2]) {
			t.Errorf("%s is %d cells full and %d plain", p[0], lipgloss.Width(p[1]), lipgloss.Width(p[2]))
		}
	}
	// A row never shifts as the selection moves over it, in either set.
	for name, g := range map[string]glyphSet{"full": fullGlyphs, "plain": plainGlyphs} {
		if lipgloss.Width(g.cursor) != lipgloss.Width(glyphBlank) {
			t.Errorf("%s: the cursor is %d cells and its blank %d", name,
				lipgloss.Width(g.cursor), lipgloss.Width(glyphBlank))
		}
	}
}

// A row that is done and a row that was passed over have to be told apart at a
// glance, and so do the track and the thumb of a scrollbar. Two glyphs that are
// the same character say nothing.
func TestNoTwoMarksInASetAreTheSame(t *testing.T) {
	for name, g := range map[string]glyphSet{"full": fullGlyphs, "plain": plainGlyphs} {
		if g.ok == g.skip {
			t.Errorf("%s: a finished row and a skipped one carry the same mark %q", name, g.ok)
		}
		if g.scrollTrack == g.scrollThumb {
			t.Errorf("%s: the scrollbar's track and thumb are both %q", name, g.scrollTrack)
		}
	}
}

// The mark turns. A spinner whose frames repeat is a spinner that looks stuck,
// which is exactly what the reduced set is here to stop.
func TestTheSpinnerActuallyChanges(t *testing.T) {
	for name, g := range map[string]glyphSet{"full": fullGlyphs, "plain": plainGlyphs} {
		if len(g.spinner) < 2 {
			t.Fatalf("%s: the spinner has %d frames", name, len(g.spinner))
		}
		distinct := map[string]bool{}
		for _, f := range g.spinner {
			distinct[f] = true
		}
		if len(distinct) < 2 {
			t.Errorf("%s: every spinner frame is the same glyph", name)
		}
	}
}

func TestTheConsoleGetsTheReducedSet(t *testing.T) {
	t.Setenv("TERM", "linux")
	if !terminalIsPlain() {
		t.Error("a Linux virtual console was not taken for one")
	}
	t.Setenv("TERM", "xterm-256color")
	if terminalIsPlain() {
		t.Error("a terminal emulator was taken for a virtual console")
	}
	t.Setenv("TERM", "")
	if !terminalIsPlain() {
		t.Error("a terminal that says nothing about itself was trusted with a font")
	}

	t.Cleanup(func() { adaptGlyphs(false) })
	adaptGlyphs(true)
	if glyphs.ok != plainGlyphs.ok {
		t.Error("adapting to a console left the full set showing")
	}
	adaptGlyphs(false)
	if glyphs.ok != fullGlyphs.ok {
		t.Error("adapting back to a terminal left the reduced set showing")
	}
}

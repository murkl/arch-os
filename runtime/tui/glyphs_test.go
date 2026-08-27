package tui

import (
	"io/fs"
	"strings"
	"testing"
	"unicode"

	"installer/internal/i18n"
	"installer/locales"

	"github.com/charmbracelet/lipgloss"
)

// consoleFont is what a Linux virtual console can draw: the printable ASCII
// range, the Latin-1 letters, and what is left of the rest once two fonts are
// laid over each other — the kernel's own, which is codepage 437 and is what a
// console wears until something loads a font over it, and Lat2-Terminus16,
// which is what the ISO loads. Neither holds everything the other does: the
// kernel font has no ellipsis, no angle quotes, no multiplication sign; the
// terminus font has no half blocks and no dark shade. What is below is in both.
//
// Written out rather than read off the running machine on purpose. What matters
// is not which font this developer happens to have loaded — it is which
// codepoints are safe on the machine the ISO boots on, and that is a fact about
// console fonts rather than about anything here.
const consoleFont = "─│┌┐└┘├┤┬┴┼░▒█■·•»«±°÷↑↓←→▲▼▶◀♦"

func inConsoleFont(s string) bool {
	return undrawable(s) == 0
}

// undrawable is the first mark in a string a console font has no glyph for, or
// zero when it can draw all of it. Latin-1 letters pass: a console font is
// built around the alphabet it is named for, and every one of them holds the
// accented letters the languages here are written in.
func undrawable(s string) rune {
	for _, r := range s {
		switch {
		case r < unicode.MaxASCII && (unicode.IsPrint(r) || r == '\n'):
		case r <= 0xff && unicode.IsLetter(r):
		case strings.ContainsRune(consoleFont, r):
		default:
			return r
		}
	}
	return 0
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

// A turning mark and a finished one are the two things in the same column, and
// the eye has to tell them apart in a still frame as well as in motion. A
// spinner that passes through the mark a done row keeps says, for a tenth of a
// second at a time, that the row it sits on is over.
func TestNothingTurningLooksLikeAFinishedRow(t *testing.T) {
	for name, g := range map[string]glyphSet{"full": fullGlyphs, "plain": plainGlyphs} {
		for _, frame := range g.spinner {
			if frame == g.ok {
				t.Errorf("%s: the spinner passes through %q, the mark a finished row keeps", name, frame)
			}
			if frame == g.skip {
				t.Errorf("%s: the spinner passes through %q, the mark a skipped row keeps", name, frame)
			}
		}
	}
}

// The marks are chosen for a console font. The words are not: they come out of
// the code and out of a catalog, and both are written by somebody with a real
// font in front of them — an ellipsis or a return symbol costs nothing there
// and is a hole in the line on a virtual console. So the words are put through
// the same set the marks come from, and this is that working.
func TestEveryWordOnScreenFitsAConsoleFont(t *testing.T) {
	t.Cleanup(func() { adaptGlyphs(false) })
	adaptGlyphs(true)

	pages := map[string]func(*harness){
		"the preset page":   func(h *harness) {},
		"a question":        func(h *harness) { h.down().enter() },
		"a list of answers": func(h *harness) { h.down().enter().typeIn("moritz").enter() },
		"the hub":           func(h *harness) { h.down().enter().typeIn("moritz").enter().enter() },
		"settings":          func(h *harness) { h.down().enter().typeIn("moritz").enter().enter().down().enter() },
		"the confirmation":  func(h *harness) { h.down().enter().typeIn("moritz").enter().enter().enter() },
		"the way out":       func(h *harness) { h.down().enter().typeIn("moritz").enter().enter().typeIn("q") },
	}
	for name, open := range pages {
		h := newHarness(t, leaveTree("true", "true"))
		open(h)
		if r := undrawable(h.screen()); r != 0 {
			t.Errorf("%s shows %q, which no console font can draw:\n%s", name, r, h.screen())
		}
	}
}

// The same, for the languages the runtime has been translated into: a catalog
// is where the marks the code was careful about come back in, because a
// translator writes the line again from scratch.
func TestEveryTranslationFitsAConsoleFont(t *testing.T) {
	files, err := fs.ReadDir(locales.FS, ".")
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range files {
		raw, err := locales.FS.ReadFile(f.Name())
		if err != nil {
			t.Fatal(err)
		}
		c, err := i18n.Parse(raw)
		if err != nil {
			t.Fatal(err)
		}
		for msgid, translation := range c.Messages {
			for _, said := range []string{msgid, translation} {
				if r := undrawable(plainGlyphs.spell.Replace(said)); r != 0 {
					t.Errorf("%s says %q, and no console font can draw %q", f.Name(), said, r)
				}
			}
		}
	}
}

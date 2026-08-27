package tui

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
)

// One box, drawn one way. Every screen renders through here and sets no styles
// of its own, which is the whole reason the interface looks like one thing.

// rule draws a horizontal line of the given width.
func rule(width int) string {
	if width < 1 {
		return ""
	}
	return ruleStyle.Render(strings.Repeat(glyphs.rule, width))
}

// pad grows a block to exactly height rows, so the footer sits at the bottom of
// the frame instead of following the content up and down as pages change.
func pad(block string, height int) string {
	lines := strings.Count(block, "\n") + 1
	if block == "" {
		lines = 0
	}
	if lines >= height {
		return block
	}
	return block + strings.Repeat("\n", height-lines)
}

// row lays a left and a right part on one line, the right pinned to the edge.
// Used for every pair in the program: brand and status, title and value, hint
// and version.
func row(left, right string, width int) string {
	gap := width - lipgloss.Width(left) - lipgloss.Width(right)
	if gap < gapS {
		// No room for both. The left is what a row is about, so the right goes.
		return truncate(left, width)
	}
	return left + field(strings.Repeat(" ", gap)) + right
}

// truncate cuts a string to width, marking that it was cut.
func truncate(s string, width int) string {
	if lipgloss.Width(s) <= width || width < 2 {
		return s
	}
	r := []rune(s)
	for len(r) > 0 && lipgloss.Width(string(r))+1 > width {
		r = r[:len(r)-1]
	}
	return string(r) + glyphs.dash
}

// wrap breaks text into lines of at most width, on word boundaries.
func wrap(s string, width int) []string {
	if width < 1 {
		return nil
	}
	var out []string
	for _, para := range strings.Split(s, "\n") {
		line := ""
		for _, w := range strings.Fields(para) {
			switch {
			case line == "":
				line = w
			case lipgloss.Width(line)+1+lipgloss.Width(w) <= width:
				line += " " + w
			default:
				out = append(out, line)
				line = w
			}
		}
		out = append(out, line)
	}
	return out
}

// paragraph renders body text at the body width: short of the frame edge by a
// golden margin, wide enough that a sentence rarely costs a second line.
//
// Where the lines fall in the yaml is not where they fall on screen. A
// description is written in a block scalar and wrapped by whoever was editing
// it to whatever their editor was that day; a blank line between two of them is
// the only break that was meant, and is the only one kept.
func paragraph(s string, width int) string {
	var out []string
	for _, para := range strings.Split(s, "\n\n") {
		if strings.TrimSpace(para) == "" {
			continue
		}
		if len(out) > 0 {
			out = append(out, "")
		}
		out = append(out, wrap(strings.Join(strings.Fields(para), " "), bodyWidth(width))...)
	}
	return textStyle.Render(strings.Join(out, "\n"))
}

// frameSize is the space a screen gets to draw in: the golden frame where the
// terminal can hold it, the terminal itself where it cannot.
//
// The numbers it returns are the *content* box. What the border and the padding
// cost is added back on in renderFrame, so no screen ever has to know they are
// there.
const frameChromeW = 2 + 2*padH // border either side, padding either side
const frameChromeH = 2 + 2*padV

func frameSize(width, height int) (w, h int) {
	w, h = frameW, frameH
	if max := width - frameChromeW; w > max {
		w = max
	}
	if max := height - frameChromeH; h > max {
		h = max
	}
	return w, h
}

// chrome is everything around a screen's own content. One value rather than a
// row of positional strings: the frame is the only place that draws all of it,
// and two of them swapped by accident would be a program that looks right and
// says the wrong thing.
type chrome struct {
	brand   string
	status  string // what this machine is, in the header
	alarm   bool   // the status is a failure being reported, not the machine's own
	mark    string // the working mark, while anything is running
	crumb   string
	body    string
	hint    string
	version string
}

// right is what stands opposite the brand: the machine's status, with the
// working mark in front of it while something is running.
//
// The mark is joined rather than wrapped. A style closed inside another takes
// the outer one down with it, and the status after it would come out in the
// terminal's own ink, background and all.
func (c chrome) right() string {
	ink := infoStyle
	if c.alarm {
		ink = failStyle
	}
	switch {
	case c.mark == "":
		return ink.Render(c.status)
	case c.status == "":
		return c.mark
	}
	return c.mark + field(" ") + ink.Render(c.status)
}

// renderFrame draws the whole screen: the brand, the breadcrumb, the body, and
// the footer, inside one box centred in the terminal.
func renderFrame(width, height int, c chrome) string {
	w, h := frameSize(width, height)
	if w < frameMinW || h < frameMinH {
		// Too small for chrome. The body alone is still useful; a frame it
		// cannot fit inside is not.
		return c.body
	}

	head := row(accentBold.Render(c.brand), c.right(), w)
	foot := row(mutedStyle.Render(c.hint), mutedStyle.Render(c.version), w)

	parts := []string{head, rule(w)}
	inner := h - 2 // the two rule lines
	if c.crumb != "" {
		parts = append(parts, c.crumb, "")
		inner -= 2
	}
	parts = append(parts, pad(c.body, inner-2), rule(w), foot)

	box := frameStyle.Width(w + 2*padH).Render(strings.Join(parts, "\n"))
	return placeOnField(width, height, box)
}

// breadcrumb renders the path to the current screen, the last segment lit
// because that is where the reader is. A path too long for the frame loses its
// head rather than its tail: the tail says where you are.
func breadcrumb(segments []string, width int) string {
	if len(segments) == 0 {
		return ""
	}
	parts := make([]string, 0, len(segments))
	for i, s := range segments {
		if i == len(segments)-1 {
			parts = append(parts, accentStyle.Render(s))
			continue
		}
		parts = append(parts, mutedStyle.Render(s))
	}
	sep := mutedStyle.Render(" " + glyphs.crumb + " ")
	out := strings.Join(parts, sep)
	for lipgloss.Width(out) > width && len(parts) > 1 {
		parts = parts[1:]
		out = mutedStyle.Render(glyphs.dash+glyphs.dash+" ") + strings.Join(parts, sep)
	}
	return out
}

// withDetail draws a list with the selected row's own sentence underneath it,
// held apart by a blank line. The sentence changes as the cursor moves, which
// is what makes a list of names readable without any of them having to be a
// sentence itself.
//
// The room it takes is reserved whether or not this row has anything to say, so
// moving the cursor never shifts the rows above it — a list that jumps under
// the hand is a list nobody trusts.
func withDetail(p *picker, width, height int) string {
	// Two lines for the sentence and a blank one above it, reserved whether or
	// not this row has anything to say — moving the cursor must not shift the
	// rows above it.
	const detailRows = 2
	const gap = 1

	body := p.View(width, height-detailRows-gap)
	// Directly under the rows rather than at the bottom of the frame: the
	// sentence belongs to the row above it, and a short list with its
	// description stranded at the far edge reads as two unrelated things.
	filled := min(p.height(width), height-detailRows-gap)

	lines := wrap(p.detail(), bodyWidth(width))
	if len(lines) > detailRows {
		lines = lines[:detailRows]
	}
	for len(lines) < detailRows {
		lines = append(lines, "")
	}
	return pad(body, filled) + strings.Repeat("\n", gap+1) + softStyle.Render(strings.Join(lines, "\n"))
}

package tui

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
	"rsc.io/qr"
)

// A value drawn as a code to scan, for the answer that is of no use inside the
// frame: a link. The machine it is wanted on is the one in somebody's hand, and
// there is no keyboard between a phone's camera and this screen.
//
// It is the one thing this program draws that is not a picture of anything. A
// paragraph that comes out slightly wrong is still readable; a code that comes
// out slightly wrong is not a code. So everything below is decided by what a
// scanner needs rather than by what the page would like — the colours it is
// drawn in, the quiet margin around it, and the refusal to draw it at all where
// there is not room for the whole thing.

// Two stacked modules to a cell, which is what makes a module square: a
// terminal cell is about twice as tall as it is wide.
const qrRows = 2

// The margin of light around the code, in modules. Four is what the
// specification asks for and what every reader is written against; two is what
// readers actually manage. The widest that fits is used, so a frame two rows
// short of the proper margin still carries a code somebody can scan rather than
// no code at all — and a frame with the room gives the margin away.
const (
	qrQuietWant = 4
	qrQuietMin  = 2
)

// Black on white, said outright rather than taken from the palette. A code is
// read by a camera, and a camera looks for dark squares on a light field — the
// convention is the format. Inverted codes are read by some scanners and not by
// others, which is the worst of both, and a code tinted to match the interface
// would be an interface that looks better and works less.
var qrInk = lipgloss.NewStyle().
	Foreground(lipgloss.Color("#000000")).
	Background(lipgloss.Color("#ffffff"))

// qrCode is a value drawn as a code, one string per row, or nil where it will
// not fit in the space given or will not encode at all.
//
// Nil rather than something smaller: a code cropped to fit, or squeezed past
// the margin a scanner finds its edges by, is a picture of a code. The page it
// belongs to shows the value as writing either way, so nothing is lost but the
// convenience — which is the right thing to lose.
func qrCode(text string, width, height int) []string {
	if text == "" {
		return nil
	}
	code, err := qr.Encode(text, qr.L)
	if err != nil {
		return nil
	}
	for quiet := qrQuietWant; quiet >= qrQuietMin; quiet-- {
		side := code.Size + 2*quiet
		if side <= width && (side+qrRows-1)/qrRows <= height {
			return draw(code, quiet)
		}
	}
	return nil
}

// draw renders the modules, two rows of them to a line of cells.
func draw(code *qr.Code, quiet int) []string {
	side := code.Size + 2*quiet
	dark := func(x, y int) bool {
		x, y = x-quiet, y-quiet
		if x < 0 || y < 0 || x >= code.Size || y >= code.Size {
			return false
		}
		return code.Black(x, y)
	}
	rows := make([]string, 0, (side+qrRows-1)/qrRows)
	for y := 0; y < side; y += qrRows {
		var b strings.Builder
		for x := range side {
			b.WriteString(cell(dark(x, y), dark(x, y+1)))
		}
		// One style over the whole row rather than one per cell: the light
		// modules are the background, and a run of them has to be painted as
		// surely as the dark ones — otherwise the terminal's own field shows
		// through the very margin the scanner is looking for.
		rows = append(rows, qrInk.Render(b.String()))
	}
	return rows
}

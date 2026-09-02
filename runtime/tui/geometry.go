package tui

// Every size in this program comes from one place, and that place is the golden
// ratio.
//
// In whole cells φ means Fibonacci: 1, 2, 3, 5, 8, 13, 21, 34, 55, 89 — each
// pair as close to φ as integers get, so a layout built from them keeps the
// same proportion at every scale without a single rounded pixel.
const (
	phi = 1.6180339887
)

const (
	// The frame. 89 is wide enough for a description to breathe and narrow
	// enough to sit in half a screen; 21 is the tallest Fibonacci number that
	// still fits the 24 rows a terminal is guaranteed to have.
	frameW = 89
	frameH = 21

	// Below this there is no room for a frame, and the content is drawn plain.
	frameMinW = 34
	frameMinH = 13

	// The spacing scale. Nothing uses a number that is not on it, and the scale
	// is kept whole rather than trimmed to what happens to be referenced today:
	// a run of names with a step missing out of its middle reads as a mistake,
	// and the next size up then gets chosen for the wrong reason.
	padV   = 1
	padH   = 2
	gapS   = 1
	gapM   = 2
	gapL   = 3
	gapXL  = 5
	gapXXL = 8
)

// split divides a width in the golden ratio: the major part is what the eye
// should land on first, the minor is what supports it. Used for the row's
// title against its value column, and for a page's body against its detail.
func split(width int) (major, minor int) {
	minor = int(float64(width)/(phi*phi) + 0.5)
	if minor < 1 {
		minor = 1
	}
	return width - minor, minor
}

// bodyWidth is how far running text may run: the width less a golden margin.
//
// A description is a sentence or two above a list, not a column of prose. The
// reading width would break it early enough to cost a second line; the bare
// frame edge would leave it flush against the border, the one block on the page
// with nothing to its right. A φ³ margin — 21 of the frame's 89 — stops it
// short of the edge while still holding the sentence on one line.
func bodyWidth(width int) int {
	return width - int(float64(width)/(phi*phi*phi)+0.5)
}

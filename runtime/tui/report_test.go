package tui

import (
	"strings"
	"testing"

	"github.com/charmbracelet/lipgloss"
)

const testLink = "https://paste.rs/xqMHY"

// Every row of a code is the same width, and there are half as many rows as
// there are columns — which is what makes a module square in a cell that is
// twice as tall as it is wide. A code drawn any other way is a picture of one.
func TestACodeIsSquareInTheCellsItIsDrawnIn(t *testing.T) {
	rows := qrCode(testLink, 40, 20)
	if len(rows) == 0 {
		t.Fatal("nothing was drawn")
	}
	width := lipgloss.Width(rows[0])
	for i, row := range rows {
		if got := lipgloss.Width(row); got != width {
			t.Fatalf("row %d is %d wide, want %d", i, got, width)
		}
	}
	if want := (width + 1) / 2; len(rows) != want {
		t.Errorf("%d rows for %d columns, want %d", len(rows), width, want)
	}
}

// The margin a scanner finds the edges by is given away as far as it fits and
// never further. A frame with the room for the full four gets them.
func TestACodeKeepsAsMuchQuietMarginAsFits(t *testing.T) {
	roomy := qrCode(testLink, 60, 30)
	tight := qrCode(testLink, 60, len(roomy)-1)
	if len(tight) == 0 {
		t.Fatal("a row short of the full margin, and nothing was drawn")
	}
	if len(tight) >= len(roomy) {
		t.Errorf("the tight code is %d rows, the roomy one %d", len(tight), len(roomy))
	}
	// Below the least a reader will manage, there is no code rather than one
	// that cannot be read.
	if got := qrCode(testLink, 60, 4); got != nil {
		t.Errorf("a code was drawn in four rows: %d rows", len(got))
	}
	if got := qrCode(testLink, 10, 30); got != nil {
		t.Error("a code was drawn in ten columns")
	}
}

func TestNothingIsDrawnForNoValue(t *testing.T) {
	if got := qrCode("", 60, 30); got != nil {
		t.Error("a code was drawn for an empty value")
	}
}

// The page is what it says and the value it produced. Everything else on it is
// there to be dropped when the frame is too short for all of it — the paragraph
// first, whole, and the mark only once there is no paragraph left.
func TestAShortFrameLosesTheParagraphBeforeTheMark(t *testing.T) {
	r := newReport("Arch Linux is installed", "One sentence.\n\nAnd a second one.", testLink)

	full := r.words(40, 40)
	if !strings.Contains(strings.Join(full, "\n"), "And a second one.") {
		t.Fatal("a frame with room for everything is missing the second paragraph")
	}

	for _, height := range []int{12, 10, 6, 4} {
		rows := r.words(40, height)
		if len(rows) > height {
			t.Errorf("at height %d the page is %d rows", height, len(rows))
		}
		text := strings.Join(rows, "\n")
		if !strings.Contains(text, "Arch Linux is installed") || !strings.Contains(text, testLink) {
			t.Errorf("at height %d the page lost what it is:\n%s", height, text)
		}
		// A paragraph is never shown half-finished.
		if strings.Contains(text, "One sentence") && !strings.Contains(text, "One sentence.") {
			t.Errorf("at height %d a sentence was cut:\n%s", height, text)
		}
	}
}

// Both blocks are centred against each other, so whichever is shorter sits in
// the middle of the taller rather than hanging off its top.
func TestTheTwoColumnsAreCentredAgainstEachOther(t *testing.T) {
	left := []string{"a"}
	right := []string{"1", "2", "3"}
	got := beside(left, right, 2)
	if len(got) != 3 {
		t.Fatalf("%d rows, want 3", len(got))
	}
	if !strings.HasPrefix(got[1], "a") {
		t.Errorf("the shorter block is not in the middle: %q", got)
	}
	if strings.HasPrefix(got[0], "a") {
		t.Errorf("the shorter block is at the top: %q", got)
	}
}

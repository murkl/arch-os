package tui

import (
	"strings"
	"testing"

	"github.com/charmbracelet/lipgloss"
)

// Every size in the program comes from the golden ratio, and the pairs below
// are the Fibonacci steps that approximate it in whole cells.
func TestSplitDividesInTheGoldenRatio(t *testing.T) {
	for _, tc := range []struct{ width, major, minor int }{
		{89, 55, 34},
		{55, 34, 21},
		{34, 21, 13},
		{13, 8, 5},
		{2, 1, 1}, // the minor never collapses to nothing
	} {
		major, minor := split(tc.width)
		if major != tc.major || minor != tc.minor {
			t.Errorf("split(%d) = %d/%d, want %d/%d", tc.width, major, minor, tc.major, tc.minor)
		}
	}
}

func TestRowPinsTheRightPartToTheEdge(t *testing.T) {
	got := row("left", "right", 20)
	if lipgloss.Width(got) != 20 {
		t.Errorf("width = %d, want 20", lipgloss.Width(got))
	}
	if !strings.HasPrefix(got, "left") || !strings.HasSuffix(got, "right") {
		t.Errorf("row = %q", got)
	}
	// No room for both, and the left is what a row is about.
	if got := row("a long left part", "right", 10); strings.Contains(got, "right") {
		t.Errorf("row = %q, want the right part dropped", got)
	}
}

func TestTruncateMarksThatItCut(t *testing.T) {
	if got := truncate("short", 10); got != "short" {
		t.Errorf("got %q", got)
	}
	got := truncate("a rather long value", 10)
	if lipgloss.Width(got) > 10 {
		t.Errorf("%q is %d wide, want at most 10", got, lipgloss.Width(got))
	}
	if !strings.HasSuffix(got, glyphs.dash) {
		t.Errorf("%q does not say it was cut", got)
	}
}

func TestWrapBreaksOnWords(t *testing.T) {
	got := wrap("one two three four five", 9)
	for _, line := range got {
		if lipgloss.Width(line) > 9 {
			t.Errorf("line %q is too wide", line)
		}
	}
	if strings.Join(got, " ") != "one two three four five" {
		t.Errorf("wrap lost or added words: %q", got)
	}
}

// Where a line ends in the yaml is not where it ends on screen — except for a
// blank line, which is the one break that was meant.
func TestParagraphKeepsOnlyDeliberateBreaks(t *testing.T) {
	got := paragraph("first\nstill first\n\nsecond", 89)
	lines := strings.Split(got, "\n")
	if len(lines) != 3 || !strings.Contains(lines[0], "first still first") {
		t.Errorf("paragraph = %q", got)
	}
	if strings.TrimSpace(lines[1]) != "" {
		t.Errorf("the blank line between paragraphs is gone: %q", got)
	}
}

func TestBreadcrumbLosesItsHeadRatherThanItsTail(t *testing.T) {
	if got := breadcrumb(nil, 40); got != "" {
		t.Errorf("empty crumb = %q", got)
	}
	segments := []string{"Settings", "Storage", "Disk"}
	got := breadcrumb(segments, 40)
	if !strings.Contains(got, "Settings") || !strings.Contains(got, "Disk") {
		t.Errorf("crumb = %q", got)
	}
	// Too narrow for all of it: where you are survives, where you came from goes.
	narrow := breadcrumb(segments, 12)
	if !strings.Contains(narrow, "Disk") {
		t.Errorf("narrow crumb = %q, want the tail kept", narrow)
	}
	if strings.Contains(narrow, "Settings") {
		t.Errorf("narrow crumb = %q, want the head dropped", narrow)
	}
}

// The frame is drawn once, in one place, and every page is inside it.
func TestTheFrameHoldsEverySide(t *testing.T) {
	out := renderFrame(100, 30, chrome{
		brand: "Test Installer", status: "3 of 12", crumb: "Settings",
		body: "the body", hint: "esc back", version: "1.0",
	})
	for _, want := range []string{"Test Installer", "3 of 12", "Settings", "the body", "esc back", "1.0", "┌", "┘"} {
		if !strings.Contains(out, want) {
			t.Errorf("the frame is missing %q:\n%s", want, out)
		}
	}
	for _, line := range strings.Split(out, "\n") {
		if lipgloss.Width(line) != 100 {
			t.Fatalf("a line is %d wide, want 100:\n%s", lipgloss.Width(line), out)
		}
	}
}

// A terminal too small for a frame still has to show the page.
func TestATerminalTooSmallForAFrameStillShowsTheBody(t *testing.T) {
	out := renderFrame(20, 6, chrome{brand: "T", body: "the body", hint: "h"})
	if out != "the body" {
		t.Errorf("out = %q, want the body alone", out)
	}
}

// A sentence under a list belongs to the row above it, and the room it takes is
// reserved whether or not that row has anything to say.
func TestTheDetailLineDoesNotShiftTheRowsAboveIt(t *testing.T) {
	with := newPicker([]item{{title: "A", detail: "About A", key: "a"}, {title: "B", key: "b"}})
	first := strings.Split(withDetail(with, 60, 12), "\n")
	with.Update(keyDown)
	second := strings.Split(withDetail(with, 60, 12), "\n")
	if len(first) != len(second) {
		t.Fatalf("the block changed height: %d then %d", len(first), len(second))
	}
	if !strings.Contains(first[len(first)-2], "About A") {
		t.Errorf("the sentence is not where it should be:\n%s", strings.Join(first, "\n"))
	}
}

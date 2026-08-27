package tui

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	keyDown = tea.KeyMsg{Type: tea.KeyDown}
	keyUp   = tea.KeyMsg{Type: tea.KeyUp}
)

func rows() []item {
	return []item{
		heading("Identity"),
		{title: "User name", value: "moritz", key: "USER"},
		{title: "Password", key: "PW"},
		heading("Storage"),
		{title: "Disk", value: "/dev/sda", key: "DISK"},
		{title: "Out of reach", key: "NOPE", disabled: true},
	}
}

// The cursor never lands anywhere pressing enter would do nothing.
func TestTheCursorSkipsWhatCannotBeChosen(t *testing.T) {
	p := newPicker(rows())
	if got := p.selected(); got != "USER" {
		t.Errorf("start = %q, want the first row that can be chosen", got)
	}
	p.Update(keyDown)
	if got := p.selected(); got != "PW" {
		t.Errorf("after down = %q", got)
	}
	p.Update(keyDown)
	if got := p.selected(); got != "DISK" {
		t.Errorf("after down = %q, want the heading skipped", got)
	}
	p.Update(keyDown)
	if got := p.selected(); got != "DISK" {
		t.Errorf("after down = %q, want an unreachable row skipped and the end to feel like an end", got)
	}
}

func TestMovementDoesNotWrap(t *testing.T) {
	p := newPicker(rows())
	p.Update(keyUp)
	if got := p.selected(); got != "USER" {
		t.Errorf("up from the first row = %q, want to stay", got)
	}
}

// An empty value under the cursor is a real answer — "no variant", "the
// default" — and is not the same thing as a list with nothing in it.
func TestChosenTellsAnEmptyAnswerFromNoAnswer(t *testing.T) {
	p := newPicker([]item{{title: "Standard", key: ""}})
	key, ok := p.chosen()
	if !ok || key != "" {
		t.Errorf("chosen = %q, %v; want an empty value that was chosen", key, ok)
	}

	empty := newPicker([]item{{title: "No matches", disabled: true}})
	if _, ok := empty.chosen(); ok {
		t.Error("a list narrowed to nothing reported a choice")
	}
}

func TestFocusReturnsTheCursorToWhereItWas(t *testing.T) {
	p := newPicker(rows())
	p.focus("DISK")
	if got := p.selected(); got != "DISK" {
		t.Errorf("selected = %q", got)
	}
	// A key that is not there, or one that cannot be chosen, leaves it alone.
	p.focus("GONE")
	p.focus("NOPE")
	if got := p.selected(); got != "DISK" {
		t.Errorf("selected = %q after focusing rows that cannot take it", got)
	}
}

// Both edges of a row stand in the same column down the whole list, which is
// the only thing that makes a column a column.
func TestValuesLineUpDownTheList(t *testing.T) {
	p := newPicker(rows())
	view := p.View(60, 10)
	var ends []int
	for _, line := range strings.Split(view, "\n") {
		if strings.Contains(line, "moritz") || strings.Contains(line, "/dev/sda") {
			ends = append(ends, lipgloss.Width(line))
		}
	}
	if len(ends) != 2 || ends[0] != ends[1] {
		t.Errorf("value column ends at %v, want one column", ends)
	}
}

// A list longer than the window gets a bar saying so, and one that fits does
// not: a track with no room to move on it says nothing a full list does not.
func TestTheScrollbarAppearsOnlyWhenThereIsSomewhereToScroll(t *testing.T) {
	p := newPicker(rows())
	if strings.Contains(p.View(60, 20), glyphs.scrollThumb) {
		t.Error("a list that fits drew a scrollbar")
	}
	if !strings.Contains(p.View(60, 3), glyphs.scrollThumb) {
		t.Error("a list that does not fit drew no scrollbar")
	}
}

// A heading belongs to the rows under it, so scrolling back to the first row of
// a group brings its heading along.
func TestScrollingBackBringsTheHeadingWithIt(t *testing.T) {
	p := newPicker(rows())
	for range 3 {
		p.Update(keyDown)
	}
	p.View(60, 3) // scrolled down to Disk
	for range 3 {
		p.Update(keyUp)
	}
	if !strings.Contains(p.View(60, 3), "Identity") {
		t.Error("scrolling back to the first row left its heading off the top")
	}
}

// The description leads the list and scrolls with it.
func TestTheDescriptionScrollsWithTheRows(t *testing.T) {
	p := newPicker(rows())
	p.describe("What this page is for.")
	if !strings.Contains(p.View(60, 10), "What this page is for.") {
		t.Error("the description is not shown")
	}
	for range 3 {
		p.Update(keyDown)
	}
	if strings.Contains(p.View(60, 3), "What this page is for.") {
		t.Error("the description stayed pinned instead of scrolling off")
	}
}

func TestNarrowKeepsWhatAQueryMatches(t *testing.T) {
	items := []item{{title: "Europe/Berlin", key: "a"}, {title: "Europe/Paris", key: "b"}, {title: "Asia/Tokyo", key: "c"}}
	if got := narrow(items, ""); len(got) != 3 {
		t.Errorf("an empty query kept %d of 3", len(got))
	}
	if got := narrow(items, "europe"); len(got) != 2 {
		t.Errorf("case-folding query kept %d of 3", len(got))
	}
	if got := narrow(items, "berlin"); len(got) != 1 || got[0].key != "a" {
		t.Errorf("narrow = %+v", got)
	}
}

// A cursor put somewhere rather than moved there gets the middle of the window:
// landing on it at the very bottom shows what comes before and nothing of what
// comes after, which reads as the end of a list it is nowhere near.
func TestAPreselectedRowLandsInTheMiddleOfTheWindow(t *testing.T) {
	var items []item
	for _, name := range []string{"a", "b", "c", "d", "e", "f", "g", "h", "i"} {
		items = append(items, item{title: name, key: name})
	}
	p := newPicker(items)
	p.focus("g")
	view := p.View(40, 5)
	lines := strings.Split(view, "\n")
	if len(lines) != 5 {
		t.Fatalf("window is %d rows, want 5", len(lines))
	}
	if !strings.Contains(lines[2], "g") {
		t.Errorf("the chosen row is not in the middle:\n%s", view)
	}
	// From the next keystroke on it is an ordinary list being walked through.
	p.Update(keyDown)
	if got := p.selected(); got != "h" {
		t.Errorf("after down = %q", got)
	}
	if lines := strings.Split(p.View(40, 5), "\n"); !strings.Contains(lines[3], "h") {
		t.Errorf("the window jumped instead of following the cursor:\n%s", p.View(40, 5))
	}
}

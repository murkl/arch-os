package tui

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// One list type for every list in the program: the main menu, a page of
// actions, a set of answers. They are all rows with a cursor, and the
// differences between them are what a row carries, not how it behaves.
//
// Hand-rendered rather than bubbles/list because a row here has a value column,
// a heading it can be grouped under, a sentence that belongs to it and a
// reachable/unreachable distinction, none of which that component knows about.

// item is one line of a list.
type item struct {
	icon     string
	title    string
	value    string // the right column: what this row is currently set to
	heading  bool   // a category label rather than something to choose
	disabled bool
	key      string // what the caller gets back

	// detail is what this row is about, in a sentence. Shown under the list
	// rather than in it: a row is a name, and a name plus an explanation on one
	// line is two rows pretending to be one.
	detail string
}

func heading(title string) item { return item{title: title, heading: true} }

type picker struct {
	items  []item
	lead   string // a page's description, scrolled above the rows rather than pinned over them
	cursor int
	top    int // first visible row, for lists longer than the frame

	// centre is set when the cursor was put somewhere rather than moved there —
	// an answer already in force, six hundred rows down a list of timezones.
	// Landing on it at the very bottom of the window shows what comes before it
	// and nothing of what comes after, which reads as the end of the list.
	centre bool
}

func newPicker(items []item) *picker {
	p := &picker{items: items}
	p.cursor = p.next(-1, 1)
	return p
}

// describe hangs a page's description above its rows, to scroll with them
// rather than stay fixed over them: the breadcrumb already says where you are,
// so the sentence saying what the page is for is content like any other and
// goes off the top as the reader moves down. Empty leaves the list starting at
// its first row, which is most of them.
func (p *picker) describe(text string) { p.lead = strings.TrimSpace(text) }

// prelude is the description as the rows that lead the list: the page's own
// sentence, wrapped to the reading width and followed by the blank that used to
// sit under it — now the first rows of the scroll rather than a header held
// above it. Nil for a list with no description.
func (p *picker) prelude(width int) []string {
	if p.lead == "" {
		return nil
	}
	lines := wrap(p.lead, bodyWidth(width))
	// One longer than the wrapped text: the last row stays empty, the gap
	// between the sentence and the first name.
	rows := make([]string, len(lines)+1)
	for i, ln := range lines {
		rows[i] = textStyle.Render(ln)
	}
	return rows
}

// next finds the nearest selectable row from i in direction d, or i itself if
// there is none. Headings and unreachable rows are skipped rather than
// selected — the cursor should never land somewhere pressing enter does nothing.
func (p *picker) next(i, d int) int {
	for j := i + d; j >= 0 && j < len(p.items); j += d {
		if !p.items[j].heading && !p.items[j].disabled {
			return j
		}
	}
	if i < 0 || i >= len(p.items) {
		return 0
	}
	return i
}

// chosen is the key of the row under the cursor, and whether there is one.
//
// The two answers are separate because a key may itself be empty: "no keyboard
// variant" is a real choice with an empty value behind it, and a list narrowed
// to nothing is not the same thing at all.
func (p *picker) chosen() (string, bool) {
	if p.cursor < 0 || p.cursor >= len(p.items) {
		return "", false
	}
	it := p.items[p.cursor]
	if it.heading || it.disabled {
		return "", false
	}
	return it.key, true
}

// selected is chosen for the lists whose rows all have a key, which is every
// list the program builds itself.
func (p *picker) selected() string {
	key, _ := p.chosen()
	return key
}

// detail is the sentence belonging to the row under the cursor, empty where
// there is none. A list whose rows all have one gains a line under it that
// changes as the cursor moves; a list whose rows have none is unchanged.
func (p *picker) detail() string {
	if p.cursor < 0 || p.cursor >= len(p.items) {
		return ""
	}
	return p.items[p.cursor].detail
}

// focus puts the cursor on a key, so returning to a list lands where you left
// and a question opens on the answer already in force.
func (p *picker) focus(key string) {
	for i, it := range p.items {
		if it.key == key && !it.heading && !it.disabled {
			p.cursor, p.centre = i, true
			return
		}
	}
}

// Update moves the cursor. Movement does not wrap: running off the end of a
// list should feel like an end, not like a loop.
func (p *picker) Update(msg tea.Msg) {
	key, ok := msg.(tea.KeyMsg)
	if !ok {
		return
	}
	switch key.String() {
	case "up", "k":
		p.cursor = p.next(p.cursor, -1)
	case "down", "j":
		p.cursor = p.next(p.cursor, 1)
	case "home", "g":
		p.cursor = p.next(-1, 1)
	case "end", "G":
		p.cursor = p.next(len(p.items), -1)
	}
}

// height is how many rows this list would take if nothing were in its way: its
// description and its items. Asked by a page that wants to put something
// directly underneath rather than at the bottom of the frame.
func (p *picker) height(width int) int {
	return len(p.prelude(width)) + len(p.items)
}

// View renders the visible window of rows: the description first, where the
// page has one, then the list, the two scrolling as one.
func (p *picker) View(width, height int) string {
	if height < 1 {
		return ""
	}
	// Wrapped at the full width, before the scrollbar takes any: the reading
	// width leaves a golden margin, so the sentence never reaches the column the
	// bar sits in whether or not there is one.
	lead := p.prelude(width)
	pre := len(lead)
	total := pre + len(p.items)
	p.scroll(height, pre)

	// A list — description and all — shorter than the window has nothing to
	// indicate: every row is already on screen, and a track with no room to
	// move on it would only say so in a more roundabout way than leaving it off
	// entirely.
	bar := total > height
	if bar {
		width -= scrollbarW
	}
	titleW, valueW := p.columns(width)

	var thumbAt, thumbLen int
	if bar {
		thumbAt, thumbLen = scrollThumb(total, height, p.top)
	}

	// A heading or a description line does not fill the row the way a title and
	// value do — each is short on purpose — so it needs padding out to the same
	// width before the scrollbar goes on, or the bar would sit wherever the
	// shortest line happens to end instead of in a column of its own.
	rowW := lipgloss.Width(glyphs.cursor) + titleW + valueW

	var b strings.Builder
	end := min(p.top+height, total)
	for i := p.top; i < end; i++ {
		if i > p.top {
			b.WriteByte('\n')
		}
		var line string
		if i < pre {
			line = lead[i]
		} else {
			j := i - pre
			line = p.line(p.items[j], j == p.cursor, titleW, valueW)
		}
		if bar {
			if gap := rowW - lipgloss.Width(line); gap > 0 {
				line += field(strings.Repeat(" ", gap))
			}
			row := i - p.top
			line += field(" ") + scrollCell(row >= thumbAt && row < thumbAt+thumbLen)
		}
		b.WriteString(line)
	}
	return b.String()
}

// scrollbarW is what the scrollbar costs: its own cell, plus the space that
// keeps it off the column in front of it — the same idea as markerW, one
// column further out.
const scrollbarW = 2

// scrollThumb works out where the thumb sits and how long it is, in rows: the
// same proportion of the track that the visible window is of the whole list,
// positioned the same fraction of the way down as the window has scrolled.
func scrollThumb(total, height, top int) (at, length int) {
	length = max(height*height/total, 1)
	if room := height - length; room > 0 {
		at = top * room / (total - height)
	}
	return at, length
}

// scrollCell is one row of the bar. The track takes the ink the frame's own
// rules and border are drawn in — it is furniture, and reads as part of the box
// rather than as something with a meaning of its own — and the thumb the ink of
// supporting text, which is as far from it as this palette goes without the
// thing starting to look like it wants choosing.
func scrollCell(onThumb bool) string {
	if onThumb {
		return softStyle.Render(glyphs.scrollThumb)
	}
	return ruleStyle.Render(glyphs.scrollTrack)
}

// columns divides the row between the title on the left and the value on the
// right. The value column is only as wide as this list's longest value needs,
// so a page of short statuses leaves the rest of the line to its titles and a
// page of long ones takes the room it has to — and either way both edges stand
// in the same place down the whole list, which is the only thing that makes a
// column a column.
//
// The golden major is the ceiling. One long value would otherwise squeeze the
// titles down to nothing, and that is the worse loss of the two: the value is
// what a row reports, but the title is what it is.
func (p *picker) columns(width int) (titleW, valueW int) {
	avail := width - lipgloss.Width(glyphs.cursor)
	widest := 0
	for _, it := range p.items {
		if it.heading {
			continue
		}
		widest = max(widest, lipgloss.Width(it.value))
	}
	valueW = widest + valueGap
	if ceiling, _ := split(avail); valueW > ceiling {
		valueW = ceiling
	}
	return avail - valueW, valueW
}

// scroll keeps the cursor inside the visible window, in the combined space of
// the description rows and the list rows: pre of the former sit ahead of the
// cursor's index, so the sentence scrolls off as the cursor moves down.
//
// Clamping alone would never bring it back — the cursor cannot climb above the
// first row. The pull-in below does: while there is room under the cursor, the
// window keeps reaching up over rows that lead the ones below them. That is a
// heading, which belongs to the rows under it, and the description, which leads
// the whole list the same way.
func (p *picker) scroll(height, pre int) {
	cur := pre + p.cursor
	// A cursor that was put here rather than moved here gets the middle of the
	// window, so what surrounds the answer is visible. Once only: from the next
	// keystroke on this is an ordinary list being walked through.
	if p.centre {
		p.centre = false
		p.top = max(cur-height/2, 0)
	}
	if cur < p.top {
		p.top = cur
	}
	if cur >= p.top+height {
		p.top = cur - height + 1
	}
	if p.top < 0 {
		p.top = 0
	}
	for p.top > 0 && cur-p.top+1 < height {
		// A list row that is not a heading stops the climb: it is a row to
		// choose, not one that leads others, so nothing above it is pulled in.
		// A description row (above pre) always leads, so it never stops it.
		if above := p.top - 1; above >= pre && !p.items[above-pre].heading {
			break
		}
		p.top--
	}
}

func (p *picker) line(it item, cursor bool, titleW, valueW int) string {
	if it.heading {
		return field(glyphBlank) + headStyle.Render(it.title)
	}

	lead := field(glyphBlank)
	if cursor {
		lead = cursorStyle.Render(glyphs.cursor)
	}

	// Only the title is cut, never the icon in front of it: the icon is a
	// styled string, and slicing runes off one would cut an escape sequence in
	// half and spill colour across the rest of the frame.
	//
	// A space is held back off the value column so the two never touch on the
	// row carrying the longest value in the list, which is the row where both
	// columns are full at once.
	title := truncate(it.title, titleW-gapS-lipgloss.Width(it.icon))
	switch {
	case it.disabled:
		title = dimStyle.Render(title)
	case cursor:
		title = accentBold.Render(title)
	default:
		title = textStyle.Render(title)
	}
	title = it.icon + title

	// The value is pinned to the right edge, a small margin short of it, so the
	// left edge stays a clean column of names to read down and the right edge is
	// a column of answers — both standing in the same place on every row, which
	// is the only thing that makes a column a column.
	value := infoStyle.Render(truncate(it.value, valueW-valueGap))
	return lead + row(title, value+field(strings.Repeat(" ", valueGap)), titleW+valueW)
}

// valueGap is the margin held between the value and the edge of the row. Flush
// against the frame, a column of values reads as having been cut off by it.
const valueGap = gapM

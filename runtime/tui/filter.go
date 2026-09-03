package tui

import (
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
)

// filter is the narrowing box a long list puts in front of itself: press / and
// type, and only the rows that match are left. It is deliberately the same box
// the search page is built around — cursor, field, list under it, one blank
// between — because narrowing one list and narrowing another are the
// same gesture and must not look like two.
//
// Closed it draws nothing at all, so a list that is never narrowed carries no
// furniture for it. Every list that can have one has one, however few rows are
// in it right now: a key that works on some folders and not others is worse than
// a key that occasionally saves nothing, because the only way to find out which
// kind of list this is would be to press it and see.
type filter struct {
	input textinput.Model
	open  bool

	// permanent is set for the one question asked before loadkeys has run:
	// its box opens already open and never closes, because the key that
	// would otherwise open or close it is typed on a layout nobody has
	// chosen yet.
	permanent bool
}

// filterKey opens the box. Slash rather than a letter, because a list already
// spends its letters on moving through it — h, j, k, l, g, G — and because it is
// what a terminal has meant by "narrow this" since long before this program.
const filterKey = "/"

// newFilter builds the box closed, the shape every list but one wants. blind
// is the one exception — see permanent — and opens it already focused.
func newFilter(blind bool) *filter {
	f := &filter{permanent: blind}
	f.input = textinput.New()
	f.input.Placeholder = labelFilterPlaceholder()
	f.input.CharLimit = 64
	styleInput(&f.input)
	if blind {
		f.open = true
		f.input.Focus()
	}
	return f
}

// query is what has been typed so far.
func (f *filter) query() string { return f.input.Value() }

// Update offers a key to the box and reports whether it took it. What a list
// owns everywhere else it still owns here — the arrows move the cursor, enter
// chooses — and every other key is a character being typed, the same split the
// search page lives by. Esc closes the box, and only once it is closed does it
// mean back: narrowing is left before the page is.
func (f *filter) Update(key tea.KeyMsg) (took bool, cmd tea.Cmd) {
	if !f.open {
		if key.String() != filterKey {
			return false, nil
		}
		f.open = true
		f.input.Focus()
		return true, textinput.Blink
	}
	switch {
	// The permanent box has nothing to close, so what would close it instead
	// leaves the question the same way it would have if the box had never
	// been there: esc and an empty backspace are handed on rather than acted
	// on here.
	case f.permanent && (cancels(key) || erases(key) && f.input.Value() == ""):
		return false, nil
	// Backspace closes the box too, but not while there is a character left in
	// it: there it is the delete key first.
	case cancels(key), erases(key) && f.input.Value() == "":
		f.close()
		return true, nil
	case confirms(key), moves(key):
		return false, nil
	}
	f.input, cmd = f.input.Update(key)
	return true, cmd
}

// close puts the box away and clears it: opening it again asks a new question,
// not the last one half-answered.
func (f *filter) close() {
	f.open = false
	f.input.Blur()
	f.input.SetValue("")
}

// View is the box as it sits over a list: the same cursor-and-field the search
// page draws, and the blank line that holds it off the rows. Empty while closed.
func (f *filter) View() string {
	if !f.open {
		return ""
	}
	return cursorStyle.Render(glyphs.cursor) + f.input.View() + "\n\n"
}

// rows is what the box costs the list below it, read off what it actually draws
// so the two can never drift apart.
func (f *filter) rows() int { return strings.Count(f.View(), "\n") }

// matches is the one definition of matching in the whole program: a plain,
// case-folding substring of the text exactly as it reads on screen. Every
// filter box asks it, so what a query finds in one it finds in the other. An
// empty query matches everything, which is the box before anything is typed
// into it.
func matches(text, query string) bool {
	return strings.Contains(strings.ToLower(text), strings.ToLower(strings.TrimSpace(query)))
}

// narrow keeps the rows a query matches, on the title — which is all a row of
// answers has. A page whose rows read as more than that — a name under a
// heading — asks matches about each part itself.
func narrow(items []item, query string) []item {
	out := make([]item, 0, len(items))
	for _, it := range items {
		if matches(it.title, query) {
			out = append(out, it)
		}
	}
	return out
}

// filterHint is a page's own key help with the box's folded into it: what the box
// does while it is up, and the key that opens it while it is not. The same shape
// the frame uses for r and f. Nil is a page whose question has not resolved a
// list yet, and it promises nothing.
func filterHint(base string, f *filter) string {
	switch {
	case f == nil:
		return base
	case f.permanent:
		return labelHintFilterBlind()
	case f.open:
		return labelHintFilter()
	}
	return base + " · " + labelHintFilterKey()
}

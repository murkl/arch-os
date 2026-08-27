package tui

import tea "github.com/charmbracelet/bubbletea"

// What may answer a question, in one place, because getting this wrong is
// silent and expensive.
//
// A terminal in the alternate screen has no scrollback to give the mouse wheel,
// so it sends arrow keys instead — a scroll arrives here as up, down, left or
// right, indistinguishable from the real key. Anything that starts, ends or
// dismisses something must therefore be a key nobody's hand lands on by
// accident: a wheel must never run an action or close the report of one that
// just ran.
//
// So: arrows move a cursor and nothing else. enter says yes, esc and backspace
// say no, and ctrl+c leaves — that is the whole vocabulary of an answer.

// confirms is the one key that means yes.
func confirms(k tea.KeyMsg) bool { return k.String() == "enter" }

// cancels is the one key that always means no. ctrl+c is not here: the model
// takes it before any screen sees it, so leaving the program works from
// everywhere.
func cancels(k tea.KeyMsg) bool { return k.String() == "esc" }

// erases is the second way to say back, and the only key here that means two
// things at once: in front of a text field it deletes a character. Which of the
// two it is belongs to the page, so a page holding a field asks for it on its
// own and only once the field has nothing left to delete.
func erases(k tea.KeyMsg) bool { return k.String() == "backspace" }

// backs is either way. Correct as it stands on a page with no text field on it;
// a page that has one must reach for cancels and erases separately.
func backs(k tea.KeyMsg) bool { return cancels(k) || erases(k) }

// answers is yes or back. Used by the pages that are only there to be read and
// closed, where the two mean the same thing.
func answers(k tea.KeyMsg) bool { return confirms(k) || backs(k) }

// moves reports the keys that move a list's cursor and nothing else. This is the
// line a page with a text box on it draws: these go to the list, everything else
// is a character being typed — so a query and a cursor share one keyboard
// without either having to know about the other.
func moves(k tea.KeyMsg) bool {
	switch k.String() {
	case "up", "down", "pgup", "pgdown":
		return true
	}
	return false
}

// scrolls reports the keys a wheel produces. Kept as its own list rather than
// as "not enter and not esc": a page that ignores scrolling still has to let
// every other key through to a text field.
func scrolls(k tea.KeyMsg) bool {
	switch k.String() {
	case "up", "down", "left", "right", "pgup", "pgdown":
		return true
	}
	return false
}

package tui

import (
	"os"
	"strings"
	"time"
)

// Every glyph the interface draws, in one place, so the set can be checked
// against a font rather than discovered to be wrong on someone's terminal.
//
// There are two sets, because there are two kinds of terminal this runs in and
// they are not equally able. A terminal emulator on a desktop draws from a font
// with tens of thousands of glyphs in it. A Linux virtual console — which is
// where an installer actually lives — draws from a console font holding at most
// 512, and a codepoint that is not in it is not drawn as anything sensible: the
// kernel puts a replacement glyph in its place, so a spinner turns into a
// character that never changes and a tick turns into a letter.
//
// So the reduced set is not a poorer version of the same idea. It is the same
// interface built out of what a console font is guaranteed to hold: the ASCII
// range, the box drawing and block characters, and the handful of punctuation
// marks every one of them inherits from codepage 437. Nothing in it is chosen
// for looking similar to what it replaces — each is chosen for being a mark
// that reads on its own.
//
// The tree's own icons are Nerd Font glyphs and are the tree's problem, not
// this file's.
type glyphSet struct {
	// cursor and its blank are the same width, so a row never shifts as the
	// selection moves over it.
	cursor string
	crumb  string
	rule   string
	dash   string

	// The scrollbar's track and thumb, one cell per row. A line and a block
	// rather than two weights of the same line: two line-drawing characters a
	// pixel apart in thickness read as one continuous rule with a fault in it,
	// which is worse than no scrollbar at all.
	scrollTrack string
	scrollThumb string

	ok   string
	fail string

	// What a task that asks first is marked with, and what a row that was
	// declined keeps instead of a tick.
	ask  string
	skip string

	// The row a list-editing screen appends after its items, structural rather
	// than one of the items themselves.
	add string

	// What a secret looks like while it is being typed. One cell wide in every
	// font, unlike the asterisk, which is drawn high in most of them and makes
	// a password field look like a footnote.
	secret string

	// focus are the density steps a block pixel passes through as the splash's
	// sweep trail cools past it: hollow at the front, filling in to solid — so
	// a fresh letter looks like it is coming into focus rather than switching
	// on at full weight in one step.
	focus []string

	// spinner turns while something runs.
	spinner []string

	// spell rewrites the marks a set has no glyph for but that turn up inside a
	// sentence rather than beside one: the return symbol a key hint names, and
	// the ellipsis a line that is still going ends on. They arrive as words
	// rather than as marks — out of the code, and out of a catalog that
	// translates them — so this is a rewriting of what is said and not one more
	// entry above.
	spell *strings.Replacer
}

// glyphBlank is the cursor's own width in empty cells. The same in either set,
// because a space is a space.
const glyphBlank = "  "

// glyphBlockPixel is the one rune the shipped block-letter wordmark draws with —
// every "on" cell of a letter is this and nothing else. The splash checks for it
// by name rather than by literal, so a custom logo built from something else
// entirely is left exactly as it is.
const glyphBlockPixel = '█'

// fullGlyphs is the interface as it is meant to look, on a terminal that can
// draw it. All of these are plain Unicode, present in any monospace font that
// can render a box.
var fullGlyphs = glyphSet{
	cursor:      "▸ ",
	crumb:       "›",
	rule:        "─",
	dash:        "·",
	scrollTrack: "│",
	scrollThumb: "█",
	ok:          "✓",
	fail:        "✕",
	ask:         "?",
	skip:        "·",
	add:         "+",
	secret:      "•",
	focus:       []string{"░", "▒", "▓", string(glyphBlockPixel)},

	// A filled quadrant sweeping round a circle: it reads as one round thing
	// rotating in place and stays inside a single cell.
	spinner: []string{"◐", "◓", "◑", "◒"},

	// Nothing to rewrite: this is the set every mark was written in.
	spell: strings.NewReplacer(),
}

// plainGlyphs is the same interface on a virtual console. Every entry here is
// in codepage 437 and in the lat* console fonts alike, which between them is
// every font a Linux console is realistically wearing — including the one the
// kernel falls back to when nothing loaded a font at all.
var plainGlyphs = glyphSet{
	cursor: "» ",
	crumb:  ">",
	rule:   "─",
	dash:   "·",

	scrollTrack: "│",
	scrollThumb: "█",

	// No console font has a tick or a cross, so both come out of ASCII, where
	// a plus and a cross are the two marks that already mean added and gone.
	// A block would read as ink rather than as a mark: at the weight of a
	// filled cell it sits on the line like a cursor stuck on the row, and a
	// column of them beside the titles is heavier than the titles.
	ok:     "+",
	fail:   "x",
	ask:    "?",
	skip:   "·",
	add:    "+",
	secret: "•",
	focus:  []string{"░", "▒", string(glyphBlockPixel)},

	// One stroke turning on the spot: upright, leaning, flat, leaning back.
	// The full set's circle is nowhere in a console font, and the shaded
	// blocks that stood here before were a whole cell of ink going on and off
	// beside the word — a mark that size next to a line of text reads as a
	// cursor stuck on the row rather than as something turning. A stroke is
	// the weight of the rules the interface is already drawn with.
	spinner: []string{"│", "/", "─", "\\"},

	// The return symbol is in no console font at all, and the ellipsis is
	// missing from the one the kernel falls back to; both are spelled out.
	spell: strings.NewReplacer("⏎", "enter", "…", "..."),
}

// glyphs is the set showing right now, read at draw time from everywhere the
// interface renders — exactly as the palette is, and for the same reason: which
// terminal this is cannot be known until it has been asked.
var glyphs = fullGlyphs

// adaptGlyphs dresses the interface in the set the terminal can actually draw.
// Separate from the asking so that what the answer does can be checked without
// a terminal to answer.
func adaptGlyphs(plain bool) {
	glyphs = fullGlyphs
	if plain {
		glyphs = plainGlyphs
	}
}

// terminalIsPlain reports whether this is a terminal drawing from a console
// font rather than from a real one.
//
// TERM is the whole of the question. A Linux virtual console says `linux` and
// nothing else does, so there is no guessing involved — and a terminal that
// says nothing at all, or says it is dumb, is one that has told us to expect
// nothing of it. Everything else is a terminal emulator with a font behind it.
func terminalIsPlain() bool {
	switch term := os.Getenv("TERM"); {
	case term == "", term == "dumb":
		return true
	default:
		return strings.HasPrefix(term, "linux")
	}
}

// spinEvery is how fast the working mark turns.
const spinEvery = 100 * time.Millisecond

// spinFrame is the frame every working mark in the program is on right now.
//
// Read off the clock rather than counted per page, and that is the whole
// point: two marks are regularly on screen at once — the header's, and the
// one a running page draws beside its own title — and two counters started at
// two different moments turn the same glyph out of step, which reads as two
// unrelated things happening rather than one. A tick still asks for the
// redraw; it no longer decides the phase.
func spinFrame() string {
	return glyphs.spinner[int(time.Now().UnixNano()/int64(spinEvery))%len(glyphs.spinner)]
}

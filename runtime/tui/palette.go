package tui

import (
	"fmt"
	"math"
	"os"
	"strconv"

	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/termenv"
)

// The palette is Nord (https://www.nordtheme.com), written out in full and
// referred to by role below. Real hex rather than the ANSI 16, because this
// runs in a terminal emulator on a configured desktop, not on a virtual
// console — and because the same sixteen values already dress the prompt, the
// editor and the system monitor. One palette for the whole environment.
const (
	nord0  = "#2e3440" // Polar Night
	nord1  = "#3b4252"
	nord2  = "#434c5e"
	nord3  = "#4c566a"
	nord4  = "#d8dee9" // Snow Storm
	nord5  = "#e5e9f0"
	nord6  = "#eceff4"
	nord7  = "#8fbcbb" // Frost
	nord8  = "#88c0d0"
	nord9  = "#81a1c1"
	nord10 = "#5e81ac"
	nord11 = "#bf616a" // Aurora
	nord12 = "#d08770"
	nord13 = "#ebcb8b"
	nord14 = "#a3be8c"
	nord15 = "#b48ead"
)

// Nord is drawn for a dark field: Frost and Aurora are mixed to sit on Polar
// Night, and on a light terminal the same values wash out to a smear. These are
// those hues taken down to where they carry against Snow Storm, at about the
// contrast the originals have against Polar Night — so the light interface reads
// with the same weight as the dark one rather than merely being legible.
const (
	lightGreen = "#4b6237"
	lightBlue  = "#2b5f6e"
	lightSteel = "#324c67"
	lightRed   = "#963c44"
)

// Neither of Nord's own neutral ramps has a step that carries against its own
// scheme: Polar Night's four sit too close together for a border in one to
// read against the field in another, and mirroring nord1 and nord3 straight
// onto Snow Storm would land both within a whisker of the paper. These four
// are built the same way the hues above are — one point each between nord3
// and nord4 — and split the same way: the hint sits at the point with more
// contrast against the field, since it is text and has to be read outright,
// and the rule and the border at the point with less, since they only have
// to be seen.
const (
	darkDim   = "#aeb5c3" // hint, footer, breadcrumb — dark scheme
	darkRule  = "#878f9f" // rule, border — dark scheme
	lightDim  = "#5a6477" // hint, footer, breadcrumb — light scheme
	lightRule = "#767f90" // rule, border — light scheme
)

// warn is a status role, not a text colour: the header's health dot flips to it
// the instant a check comes back unhappy, and it has to catch the eye at a
// glance. Nord's one yellow (nord13) is a body-text pastel that at dot size
// reads as off-white rather than a warning, so warn takes a saturated amber of
// its own — bright on Polar Night, taken down to hold its contrast on Snow
// Storm, so the sign is the same weight in either scheme.
const (
	darkAmber  = "#ffb02e" // warn — dark scheme
	lightAmber = "#9a5000" // warn — light scheme
)

// fail is the one role that is regularly a paragraph rather than a word: when a
// stage dies, what the tool said is read line by line, and it is the most
// important text this program ever puts on screen. Nord's own red (nord11) sits
// at 3.05 against Polar Night — enough for a heading, short of what a block of
// text needs. This is that red lightened until it clears WCAG AA for body text,
// which keeps the hue and only stops it being one nobody can read.
const darkRed = "#f27983" // fail — dark scheme

// scheme is one whole set of roles. There are two, one for each kind of
// terminal, and nothing outside this file knows which of them is showing —
// which is what keeps the light interface from being a second design.
type scheme struct {
	// accent is the primary. Green is the colour of a thing that is on and
	// working, which is what this program is mostly reporting.
	accent lipgloss.Color

	bezel lipgloss.Color // the one field: the splash, the frame's interior, everything outside it too
	sunk  lipgloss.Color // rules and the border line, far enough off the bezel to read against it
	muted lipgloss.Color // the footer, the breadcrumb, a row that cannot be chosen
	soft  lipgloss.Color // supporting text
	text  lipgloss.Color // body text, and only while the opening fades it in — see buildStyles
	info  lipgloss.Color // a value the system reports
	head  lipgloss.Color // a heading inside the body
	warn  lipgloss.Color
	fail  lipgloss.Color

	// good is the third of the status roles, opposite fail: something worked,
	// and worked for good. It is not the accent — the accent is whatever colour
	// the runtime dressed itself in, and an installation that finished has to read as
	// finished in an installer painted red as readily as in one painted green.
	// So it is green here and stays green, the one colour that means this
	// everywhere a person has ever looked at a machine.
	good lipgloss.Color
}

var darkScheme = scheme{
	accent: nord14,
	bezel:  nord0,
	sunk:   darkRule, // nord2 sat too close to the bezel for the frame to read against it
	muted:  darkDim,
	soft:   nord4,
	text:   nord6,
	info:   nord8,
	head:   nord9,
	warn:   darkAmber,
	fail:   darkRed,
	good:   nord14,
}

var lightScheme = scheme{
	accent: lightGreen,
	bezel:  nord6,
	sunk:   lightRule,
	muted:  lightDim,
	soft:   nord2,
	text:   nord0,
	info:   lightBlue,
	head:   lightSteel,
	warn:   lightAmber,
	fail:   lightRed,
	good:   lightGreen,
}

var (
	// base is the scheme the terminal calls for.
	base = darkScheme

	// colors is that scheme with the runtime's accent on it: what is actually
	// showing, and the only thing the styles read.
	colors = darkScheme

	// accentHex is what the runtime asked for, kept because it has to be laid on
	// again whenever the scheme underneath it changes.
	accentHex string

	// terminalDark is what the terminal answered, kept because the question can
	// only be put once, before the key reader starts.
	terminalDark = true
)

// Adapt dresses the interface for the terminal it is about to draw on: what it
// is painted, and which glyphs it can actually draw. Anything the terminal will
// not answer is taken as dark, which is what a terminal is unless somebody
// changed it.
//
// It has to be asked before the program takes the terminal over: the answer
// arrives as an escape sequence on stdin, and once there is a key reader running
// it would be read as somebody typing.
func Adapt() {
	terminalDark = terminalIsDark()
	adapt(terminalDark)
	adaptGlyphs(terminalIsPlain())
}

// adapt dresses the interface for a terminal of the given kind. It is separate
// from the asking so that what the answer does can be checked without a
// terminal to answer.
//
// The field itself is left alone: whatever the terminal is painted, that is what
// the interface sits on. There is no setting for it, and that is deliberate —
// this program runs on somebody else's terminal for twenty minutes and then is
// never seen again, which is no place to insist on a background of its own.
func adapt(dark bool) {
	base = darkScheme
	if !dark {
		base = lightScheme
	}
	apply()
}

// terminalIsDark puts the question to the terminal: an escape sequence asking
// what colour it is painted, and the answer read back off the same handle.
//
// termenv will not ask anything whose TERM says tmux, screen or dumb, on the
// reasoning that a multiplexer can have several terminals attached and so has no
// one answer to give. tmux does answer, though — it learned the colour from
// whichever terminal is attached and passes it along — so inside tmux the
// question goes out under a TERM that termenv is willing to ask, and only there.
//
// A terminal with no colour to report is not asked at all. A virtual console has
// sixteen slots painted by whoever booted the machine and nothing to say about
// what is behind them; a terminal calling itself dumb has said as much outright.
// Either way the answer is the dark this falls back to, and asking for it costs
// a round trip on the console and five seconds on anything that answers nothing.
// Which terminals those are is the question next door: the ones with no font of
// their own to draw with.
func terminalIsDark() bool {
	if terminalIsPlain() {
		return true
	}
	var opts []termenv.OutputOption
	if os.Getenv("TMUX") != "" {
		opts = append(opts, termenv.WithEnvironment(plainTerm{}))
	}
	return termenv.NewOutput(os.Stdout, opts...).HasDarkBackground()
}

// plainTerm is the environment as it stands, except that TERM names an ordinary
// terminal. It is only ever handed to the one question above, never to anything
// that decides what the interface may draw — tmux is still the thing being
// talked to, and it is still the one being asked.
type plainTerm struct{}

func (plainTerm) Environ() []string { return os.Environ() }

func (plainTerm) Getenv(key string) string {
	if key == "TERM" {
		return "xterm-256color"
	}
	return os.Getenv(key)
}

// SetAccent lets the runtime pick the primary. Everything built from it is rebuilt
// here, so nothing bakes the colour in at package init.
func SetAccent(hex string) {
	accentHex = hex
	apply()
}

// apply lays the runtime's accent on the scheme the terminal called for and rebuilds
// everything made from the two. It starts from base every time rather than from
// what is showing, so a runtime that drops its accent gets the scheme's own back.
func apply() {
	colors = base
	if accentHex != "" {
		colors.accent = readable(lipgloss.Color(accentHex), base.bezel)
	}
	buildStyles()
}

// The interface is built dark and stays that way until somebody asks the
// terminal, so that a run with no terminal to ask — a test, a piped -list — is
// not sat waiting on an answer that is never coming.
func init() { SetAccent("") }

// minContrast is the ratio at which text is held to be readable on the field
// behind it: WCAG AA for body text.
const minContrast = 4.5

// readable takes a colour far enough from the field it sits on to be read
// against it, and no further. The runtime names one accent and cannot know which
// terminal it will be shown in, so a green picked against Polar Night would
// otherwise arrive on white paper as a pale smudge.
//
// What it moves towards is black or white, whichever the field is not. That
// darkens or lightens without turning the hue, so a green stays a green — it
// just stops being one nobody can see.
//
// A colour in some notation other than #rrggbb is left exactly as it was written
// it: an accent this cannot measure is still an accent somebody chose.
func readable(c, bezel lipgloss.Color) lipgloss.Color {
	if _, ok := rgb(string(c)); !ok {
		return c
	}
	toward := lipgloss.Color("#ffffff")
	if luminance(bezel) > 0.5 {
		toward = "#000000"
	}
	for t := 0.0; t <= 1; t += 0.05 {
		out := blend(c, toward, t)
		if contrast(out, bezel) >= minContrast {
			return out
		}
	}
	return toward
}

// fadeLevel is how much of the palette is showing: 1 is the full palette, 0 is
// the bezel it all sits on. Running it down and back up is what carries the
// splash into the interface, and it only works because every colour reaches a
// style through fade() rather than being used directly.
var fadeLevel = 1.0

// setFade puts the palette at a level and rebuilds everything made from it.
func setFade(level float64) {
	fadeLevel = min(max(level, 0), 1)
	buildStyles()
}

// fade blends a role towards the bezel. A terminal cannot dissolve one screen
// into another, so what fades is the ink rather than the picture — at two dozen
// frames a second the eye takes it for the same thing.
func fade(c lipgloss.Color) lipgloss.Color {
	if fadeLevel >= 1 {
		return c
	}
	return blend(c, colors.bezel, 1-fadeLevel)
}

// blend mixes a into b, t of the way. A pair it cannot read comes back as a —
// which only happens to an accent named in some notation other than
// #rrggbb, and an accent that does not blend beats an accent that turns to noise.
func blend(a, b lipgloss.Color, t float64) lipgloss.Color {
	from, ok := rgb(string(a))
	to, toOK := rgb(string(b))
	if !ok || !toOK {
		return a
	}
	var out [3]int
	for i := range out {
		out[i] = int(from[i] + (to[i]-from[i])*t + 0.5)
	}
	return lipgloss.Color(fmt.Sprintf("#%02x%02x%02x", out[0], out[1], out[2]))
}

// contrast is the WCAG ratio between two colours: 1 for a pair that is the same,
// 21 for black on white.
func contrast(a, b lipgloss.Color) float64 {
	la, lb := luminance(a), luminance(b)
	if la < lb {
		la, lb = lb, la
	}
	return (la + 0.05) / (lb + 0.05)
}

// luminance is relative luminance per WCAG: the channels taken out of sRGB's
// gamma and weighted by how much the eye makes of each. It is only ever asked
// about a literal that has already been read, and answers black for anything
// else.
func luminance(c lipgloss.Color) float64 {
	ch, ok := rgb(string(c))
	if !ok {
		return 0
	}
	var lin [3]float64
	for i, v := range ch {
		v /= 255
		if v <= 0.03928 {
			lin[i] = v / 12.92
			continue
		}
		lin[i] = math.Pow((v+0.055)/1.055, 2.4)
	}
	return 0.2126*lin[0] + 0.7152*lin[1] + 0.0722*lin[2]
}

// rgb reads a "#rrggbb" literal into channels.
func rgb(hex string) (c [3]float64, ok bool) {
	if len(hex) != 7 || hex[0] != '#' {
		return c, false
	}
	v, err := strconv.ParseUint(hex[1:], 16, 32)
	if err != nil {
		return c, false
	}
	return [3]float64{float64(v >> 16 & 0xff), float64(v >> 8 & 0xff), float64(v & 0xff)}, true
}

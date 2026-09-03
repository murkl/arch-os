package tui

import (
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// The one thing here that is not part of the interface: no breadcrumb, no
// footer, no keys, no frame. A moment before the interface rather than a page
// inside it — but the same program, because leaving the alternate screen and
// entering it again would blink the shell through the middle of the start.
//
// Under the wordmark stands the version, not the title: the wordmark already
// says the name. It fades in last, once the wordmark has settled, so the two
// never compete for the eye.

const (
	// animEvery is one animation frame — the rate the wordmark sweeps in and
	// the rate the interface comes up.
	animEvery = time.Second / 24

	// splashFor is how long the logo stays. 1.618 seconds, because everything
	// else here is proportioned that way too and it is long enough to read a
	// wordmark.
	splashFor = 1618 * time.Millisecond

	// fadeFor is the handover — the splash divided by φ³, long enough to read
	// as the logo giving way and short enough that nobody waits through it. It
	// is spent four times: first as the wordmark sweeping into view, then as
	// the pause held after the version has faded in — long enough to actually
	// read it, not just catch it going past — then as the last stretch of the
	// splash dimming out, then as long again with the interface coming up.
	fadeFor = 382 * time.Millisecond

	// versionFor is how long the version takes to fade in once the wordmark
	// has settled — fadeFor again, divided by φ, since it is the smaller of
	// the two things arriving and the last one to. It is not simultaneous
	// with the wordmark: the version is the last word, not a caption reading
	// along beside it.
	versionFor = 236 * time.Millisecond

	// versionRest is how far past muted the version's resting colour sits,
	// blended toward the field it sits on — a build number is the least
	// important thing on the splash, dimmer even than the muted rows the rest
	// of the interface uses for a footer or a breadcrumb.
	versionRest = 0.3

	// trailCols is how many columns behind the sweep's front a letter still
	// carries a trace of it — cooling from the accent back to its row's own
	// resting colour, and, for a block pixel, filling in from hollow to solid
	// — long enough to read as a light passing through the word and coming
	// into focus behind it, short enough that most of a settled wordmark is
	// already at rest.
	trailCols = gapXXL
)

type animMsg struct{}

func animTick() tea.Cmd {
	return tea.Tick(animEvery, func(time.Time) tea.Msg { return animMsg{} })
}

// logoLines squares off a block of text. Trailing spaces do not survive every
// editor, and a ragged block would be centred line by line — which would pull
// the wordmark apart.
func logoLines(logo string) []string {
	return padLines(strings.Split(strings.TrimRight(logo, "\n"), "\n"))
}

// padLines squares a block off to its own widest line, right-padding every
// other one out to match.
func padLines(lines []string) []string {
	w := 0
	for _, l := range lines {
		if n := lipgloss.Width(l); n > w {
			w = n
		}
	}
	out := make([]string, len(lines))
	for i, l := range lines {
		out[i] = l + strings.Repeat(" ", w-lipgloss.Width(l))
	}
	return out
}

type splashModel struct {
	// rows is the logo, squared off and split in two: the eyebrow — the OS
	// name, dim, standing over the wordmark — and the headline, the one line
	// this program actually is, lit in the accent. Everything from the first
	// blank line on is the headline; a logo with none is headline only.
	rows      []string
	titleRows int

	version string
	total   time.Duration
	elapsed time.Duration
}

func newSplash(logo, version string) *splashModel {
	rows := logoLines(logo)
	title := 0
	for title < len(rows) && strings.TrimSpace(rows[title]) != "" {
		title++
	}
	// total runs one fadeFor past splashFor's own span: the reading pause held
	// after the version arrives, on top of the time the wordmark itself gets.
	return &splashModel{rows: rows, titleRows: title, version: version, total: splashFor + fadeFor}
}

// advance moves the splash on one frame and reports whether it is over.
func (m *splashModel) advance() (done bool) {
	m.elapsed += animEvery
	return m.elapsed >= m.total
}

// skip cuts the logo short: nobody should have to sit through a wordmark twice.
// It jumps to the start of the fade rather than past it, so dismissing the
// splash still looks like the splash leaving.
func (m *splashModel) skip() {
	if start := m.total - fadeFor; m.elapsed < start {
		m.elapsed = start
	}
}

// light is how much of the palette the splash is showing: all of it until the
// last stretch, then down to none, so the logo dissolves into the background
// that the interface then comes up out of.
func (m *splashModel) light() float64 {
	left := m.total - m.elapsed
	if left >= fadeFor {
		return 1
	}
	return float64(left) / float64(fadeFor)
}

// revealed is how far the wordmark has swept into view, left to right: 0 at
// the very start, 1 once the build is done, and held there for the rest of
// the splash — the letters do not sweep in twice.
func (m *splashModel) revealed() float64 {
	if m.elapsed >= fadeFor {
		return 1
	}
	return float64(m.elapsed) / float64(fadeFor)
}

// versionShown is how far the version has faded in: 0 until the wordmark has
// long since settled, 1 a full fadeFor before the splash starts dimming out —
// so that once it arrives it sits there and is actually read, rather than
// fading in just as the handover to the interface begins.
func (m *splashModel) versionShown() float64 {
	start := m.total - 2*fadeFor - versionFor
	switch t := m.elapsed - start; {
	case t <= 0:
		return 0
	case t >= versionFor:
		return 1
	default:
		return float64(t) / float64(versionFor)
	}
}

func (m *splashModel) View(width, height int) string {
	return placeOnField(width, height, m.compose())
}

// compose draws the wordmark, row by row, and puts the version underneath.
func (m *splashModel) compose() string {
	revealed := m.revealed()
	front := revealed * float64(lipgloss.Width(m.rows[0]))

	rows := make([]string, len(m.rows))
	for dy, line := range m.rows {
		resting, bold := colors.accent, true
		if dy < m.titleRows {
			resting, bold = colors.soft, false
		}
		rows[dy] = sweepLine(line, front, revealed >= 1, resting, bold)
	}
	return m.sign(strings.Join(rows, "\n"))
}

// sweepLine renders one row up to front: a letter inside the trail comes into
// focus on trailProgress — colour cooling from the accent down to resting,
// and, for a solid block pixel, density filling in from hollow to solid —
// and anything at or beyond front — the sweep has not reached it yet — is
// unlit field, exactly like the gap between two letters that have already
// arrived.
//
// Once the build is done, front sits at the row's own width forever — the
// last few letters would otherwise stay a shade and a density off resting for
// the whole rest of the splash, the trail's tail caught permanently mid-cool.
// settled pins the progress at 1 outright once that happens, since there is
// no front left to trail behind.
func sweepLine(line string, front float64, settled bool, resting lipgloss.Color, bold bool) string {
	style := baseStyle.Bold(bold)
	var b strings.Builder
	for dx, r := range []rune(line) {
		if r == ' ' || float64(dx) >= front {
			b.WriteString(field(" "))
			continue
		}
		t := 1.0
		if !settled {
			t = trailProgress(dx, front)
		}
		glyph := sweepGlyph(r, t)
		b.WriteString(style.Foreground(fade(sweepColor(t, resting))).Render(glyph))
	}
	return b.String()
}

// trailProgress is how far a column at dx sits behind the sweep's front, as a
// fraction of trailCols: 0 right at the front, 1 a full trailCols behind it
// or further. Colour and density both move on this one scale, so a letter's
// shading and its sharpness resolve together rather than on two clocks.
func trailProgress(dx int, front float64) float64 {
	switch t := (front - float64(dx)) / trailCols; {
	case t < 0:
		return 0
	case t > 1:
		return 1
	default:
		return t
	}
}

// sweepColor is the foreground a letter takes at a given point in the trail:
// full accent at the front (t=0), cooling to resting by the time the trail
// runs out (t=1).
func sweepColor(t float64, resting lipgloss.Color) lipgloss.Color {
	return blend(colors.accent, resting, t)
}

// sweepGlyph is what a rune renders as at a given point in the trail: a solid
// block pixel comes into focus through glyphs.focus' density steps as t goes
// from the front to fully resolved. Anything else — a runtime's own logo may
// draw with letters or icons rather than block pixels — renders as itself
// throughout; only the shipped block font resolves like this.
func sweepGlyph(r rune, t float64) string {
	if r != glyphBlockPixel {
		return string(r)
	}
	return glyphs.focus[int(t*float64(len(glyphs.focus)-1)+0.5)]
}

// sign puts the version under a block, centred, with gapS blank lines of its
// own — the same single line the logo itself uses to part the eyebrow from
// the wordmark, so the version reads as its own caption underneath rather
// than a third row of the mark itself.
//
// Its colour comes from versionShown rather than mutedStyle outright: the
// version fades in on its own, out of the field it sits on, the same way the
// whole splash later dissolves into the interface — just the ink moving, not
// the letters. Dimmed past muted by versionRest: this is a build number, the
// least important thing on the screen, not a second line of copy competing
// with the wordmark above it.
func (m *splashModel) sign(block string) string {
	line := baseStyle.Width(lipgloss.Width(block)).Align(lipgloss.Center)

	resting := blend(colors.muted, colors.bezel, versionRest)
	shown := blend(resting, colors.bezel, 1-m.versionShown())
	version := baseStyle.Foreground(fade(shown)).Render(m.version)

	parts := make([]string, 0, gapS+2)
	parts = append(parts, block)
	for range gapS {
		parts = append(parts, line.Render(""))
	}
	parts = append(parts, line.Render(version))

	return lipgloss.JoinVertical(lipgloss.Center, parts...)
}

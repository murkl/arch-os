package tui

import (
	"testing"

	"github.com/charmbracelet/lipgloss"
)

// A folder names one accent and cannot know which terminal it will be shown in.
// A green picked against a dark field would otherwise arrive on white paper as
// a pale smudge nobody can read.
func TestAnAccentIsTakenToWhereItCanBeRead(t *testing.T) {
	for _, field := range []lipgloss.Color{darkScheme.bezel, lightScheme.bezel} {
		for _, accent := range []string{"#1793d1", "#a3be8c", "#ffffff", "#000000"} {
			got := readable(lipgloss.Color(accent), field)
			if c := contrast(got, field); c < minContrast {
				t.Errorf("%s on %s has contrast %.2f, want at least %.1f", accent, field, c, minContrast)
			}
		}
	}
}

// An accent this cannot measure is still an accent somebody chose.
func TestAnAccentInSomeOtherNotationIsLeftAlone(t *testing.T) {
	if got := readable(lipgloss.Color("5"), darkScheme.bezel); got != lipgloss.Color("5") {
		t.Errorf("got %q, want it untouched", got)
	}
}

// Both schemes have to carry, not merely be legible: the light interface is the
// same design, not a second one.
func TestBothSchemesAreReadableOnTheirOwnField(t *testing.T) {
	for name, s := range map[string]scheme{"dark": darkScheme, "light": lightScheme} {
		for role, c := range map[string]lipgloss.Color{
			"text": s.text, "soft": s.soft, "muted": s.muted,
			"info": s.info, "head": s.head, "warn": s.warn, "fail": s.fail, "accent": s.accent,
		} {
			if got := contrast(c, s.bezel); got < minContrast {
				t.Errorf("%s %s has contrast %.2f against its field", name, role, got)
			}
		}
		// The rule and the border only have to be seen, not read.
		if got := contrast(s.sunk, s.bezel); got < 1.6 {
			t.Errorf("%s rule has contrast %.2f, too close to the field to see", name, got)
		}
	}
}

func TestContrastAndLuminanceAgreeWithTheStandard(t *testing.T) {
	black, white := lipgloss.Color("#000000"), lipgloss.Color("#ffffff")
	if got := contrast(black, white); got < 20.9 || got > 21.1 {
		t.Errorf("black on white = %.2f, want 21", got)
	}
	if got := contrast(white, white); got != 1 {
		t.Errorf("white on white = %.2f, want 1", got)
	}
}

// The opening fades the whole interface up out of the background, and it only
// works because every colour reaches a style through fade().
func TestFadingRunsFromTheFieldToTheFullPalette(t *testing.T) {
	defer setFade(1)
	setFade(0)
	if got := fade(colors.accent); got != colors.bezel {
		t.Errorf("fully faded accent = %q, want the field itself", got)
	}
	setFade(1)
	if got := fade(colors.accent); got != colors.accent {
		t.Errorf("unfaded accent = %q", got)
	}
	// Out of range is clamped rather than trusted.
	setFade(2)
	if fadeLevel != 1 {
		t.Errorf("fadeLevel = %v", fadeLevel)
	}
	setFade(-1)
	if fadeLevel != 0 {
		t.Errorf("fadeLevel = %v", fadeLevel)
	}
}

// Which scheme is worn follows the terminal and nothing else: there is no
// setting for it, and the interface never paints a background of its own.
func TestTheSchemeFollowsTheTerminal(t *testing.T) {
	defer adapt(true)
	adapt(false)
	if colors.bezel != lightScheme.bezel {
		t.Error("a light terminal did not get the light scheme")
	}
	adapt(true)
	if colors.bezel != darkScheme.bezel {
		t.Error("a dark terminal did not get the dark scheme")
	}
}

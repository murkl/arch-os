package cli

import (
	"strings"
	"testing"

	"github.com/murkl/arch-os/runtime/internal/spec"
)

func page() Page {
	return Page{
		Runtime: &spec.Runtime{
			Name: "Test OS",
			Help: spec.Help{
				About:   "Put something on this machine.",
				Command: "test-os",
				Examples: []spec.Example{
					{Run: "test-os --installer", About: "Install, answering as it goes."},
				},
			},
		},
		Flags:   []spec.Flag{{Name: "force", Title: "Ask nothing."}, {Name: "help", Alias: "h", Title: "This page."}},
		Command: "test-os",
		Version: "1.2.3",
	}
}

func TestThePageSaysWhatThisIsAndHowItIsTyped(t *testing.T) {
	out := page().Render()
	for _, want := range []string{
		"Test OS 1.2.3",
		"  Put something on this machine.",
		"  test-os [options]",
		"  --force",
		"  --help, -h",
		"  test-os --installer",
		"    Install, answering as it goes.",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("the page has no %q in it:\n%s", want, out)
		}
	}
}

// Every description on the page begins in one column, so two lists read as one
// page. It gives way to a name too wide for it and no further.
func TestOneColumnHoldsForTheWholePage(t *testing.T) {
	p := page()
	p.Flags = append(p.Flags, spec.Flag{Name: "conf", Value: "path", Title: "Where the answers are kept."})
	out := p.Render()
	at := -1
	for line := range strings.SplitSeq(out, "\n") {
		if !strings.HasPrefix(line, "  --") {
			continue
		}
		gap := strings.Index(line[2:], "  ") + 2
		where := gap + strings.IndexFunc(line[gap:], func(r rune) bool { return r != ' ' })
		if at == -1 {
			at = where
		}
		if where != at {
			t.Errorf("%q begins its text at %d, not %d — the page has two columns", line, where, at)
		}
	}
	if at < minW {
		t.Errorf("the column is at %d, which is inside the golden margin of %d", at, minW)
	}
}

// A name too long for the column takes the line to itself rather than pushing
// the whole list out of true — but only past the width the column may grow to.
func TestATooLongNameTakesTheLineToItself(t *testing.T) {
	p := page()
	p.Flags = []spec.Flag{{Name: strings.Repeat("x", 40), Value: "value", Title: "Long."}}
	out := p.Render()
	if !strings.Contains(out, "xxx <value>\n") {
		t.Errorf("a name wider than the column did not take its own line:\n%s", out)
	}
	if !strings.Contains(out, strings.Repeat(" ", maxW)+"Long.") {
		t.Errorf("its text did not begin in the column:\n%s", out)
	}
}

// A run that offers one module has no choice to describe, and says so by not
// putting a list of one on the page.
func TestOneModuleIsNoList(t *testing.T) {
	p := page()
	if strings.Contains(p.Render(), "Modules") {
		t.Error("a page with no modules on it has a Modules heading")
	}
	if !strings.Contains(p.Render(), "test-os [options]") {
		t.Error("the usage line offers a module where there is nothing to choose")
	}
}

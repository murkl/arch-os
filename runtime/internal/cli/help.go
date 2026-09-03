package cli

import (
	"strings"

	"github.com/charmbracelet/x/ansi"

	"github.com/murkl/arch-os/runtime/internal/i18n"
	"github.com/murkl/arch-os/runtime/internal/spec"
)

// The page a run puts up when it is asked what it is.
//
// Its proportions are the interface's own: 89 columns is the frame, and a
// description begins a φ³ margin in — 21 — which is the same margin every page
// of the interface keeps its running text off the frame's edge by. The column
// gives way to a name too wide for it, as far as the φ² split and no further,
// so one long flag sets the list a little wider instead of standing in a list
// that no longer lines up.
const (
	pageW = 89
	minW  = 21
	maxW  = 34
	step  = 2
	gap   = 2
)

// Page is everything --help is drawn from: the product, what it offers, the one
// module that was named if one was, and the runtime's own flags.
//
// A module named narrows the whole page to it — what it is, what it is typed
// as, what it takes. Nothing else is worth reading at that point, and a page
// listing every flag of every module is a page nobody finishes.
type Page struct {
	Runtime *spec.Runtime
	Modules []*spec.Module
	Module  *spec.Module
	Flags   []spec.Flag
	Command string
	Version string
}

// Render writes the page.
func (p Page) Render() string {
	var b strings.Builder
	at := p.column()
	p.head(&b)
	p.usage(&b)
	p.modules(&b, at)
	p.options(&b, at)
	p.examples(&b)
	return b.String()
}

// column is where every description on this page begins: the golden margin, or
// as much more as the widest name on it needs, up to the golden split.
//
// One column for the whole page rather than one per list. Two lists that begin
// their text in two different places read as two pages, and this is one.
func (p Page) column() int {
	at := minW
	for _, label := range p.labels() {
		if width := step + ansi.StringWidth(label) + gap; width > at {
			at = width
		}
	}
	return min(at, maxW)
}

// labels is every name this page puts in that column.
func (p Page) labels() []string {
	var out []string
	if p.Module == nil {
		for _, mod := range p.Modules {
			out = append(out, "--"+mod.ID())
		}
	} else {
		for _, f := range p.Module.Flags() {
			out = append(out, label(f))
		}
	}
	for _, f := range p.Flags {
		out = append(out, label(f))
	}
	return out
}

// head is the name of what this is, the version it is at, and the one sentence
// under it.
func (p Page) head(b *strings.Builder) {
	name, about := p.Runtime.Name, i18n.T(p.Runtime.Help.About)
	if p.Module != nil {
		name, about = p.Module.Name(), p.Module.Help()
	}
	b.WriteString(strings.TrimSpace(name))
	b.WriteByte(' ')
	b.WriteString(p.Version)
	b.WriteByte('\n')
	if about != "" {
		b.WriteByte('\n')
		indented(b, step, about, pageW-step)
	}
}

// usage is the shape of a command line, with the parts that are a choice in
// brackets — the one line somebody reads before typing.
func (p Page) usage(b *strings.Builder) {
	line := p.Command
	switch {
	case p.Module != nil:
		line += " --" + p.Module.ID()
	case len(p.Modules) > 1:
		line += " [" + i18n.T("module") + "]"
	}
	section(b, i18n.T("Usage"))
	b.WriteString(pad(step))
	b.WriteString(line)
	b.WriteString(" [")
	b.WriteString(i18n.T("options"))
	b.WriteString("]\n")
}

// modules is what this product offers, each with what it is under its name.
// Left off where there is only one: a choice of one is not a choice, and the
// run opens it without asking.
func (p Page) modules(b *strings.Builder, at int) {
	if p.Module != nil || len(p.Modules) < 2 {
		return
	}
	section(b, i18n.T("Modules"))
	for _, mod := range p.Modules {
		row(b, at, "--"+mod.ID(), mod.Help())
	}
}

// options is what a command line may carry: the named module's own first,
// because they are what was asked about, and the runtime's under them.
func (p Page) options(b *strings.Builder, at int) {
	section(b, i18n.T("Options"))
	if p.Module != nil {
		if flags := p.Module.Flags(); len(flags) > 0 {
			rows(b, at, flags)
			b.WriteByte('\n')
		}
	}
	rows(b, at, p.Flags)
}

// examples are the whole command lines worth copying, each with what it does
// under it. They belong to the product rather than to any one module, so they
// are read on the page about the product.
func (p Page) examples(b *strings.Builder) {
	if p.Module != nil || len(p.Runtime.Help.Examples) == 0 {
		return
	}
	section(b, i18n.T("Examples"))
	for i, e := range p.Runtime.Help.Examples {
		if i > 0 {
			b.WriteByte('\n')
		}
		b.WriteString(pad(step))
		b.WriteString(e.Run)
		b.WriteByte('\n')
		indented(b, step*2, i18n.T(e.About), pageW-step*2)
	}
}

// rows is a list of flags, each as it is written and what it does beside it.
func rows(b *strings.Builder, at int, flags []spec.Flag) {
	for _, f := range flags {
		row(b, at, label(f), f.Title)
	}
}

// label is one flag as it is written on a command line: its name, and what it
// takes where it takes anything.
func label(f spec.Flag) string {
	out := "--" + f.Name
	if f.Alias != "" {
		out += ", -" + f.Alias
	}
	if !f.Switch() {
		out += " <" + f.Value + ">"
	}
	return out
}

// section is a heading with a blank line either side of it. Nothing is bold and
// nothing is coloured: this page is as often read through a pipe as on a screen,
// and a heading on a line of its own is legible either way.
func section(b *strings.Builder, title string) {
	b.WriteByte('\n')
	b.WriteString(title)
	b.WriteString("\n\n")
}

// row is one line of a list: what it is written as, in its own column, with
// what it does beside it. A name too long for the column takes the line to
// itself and the text begins on the next one, rather than pushing a whole list
// out of true for the sake of one row.
func row(b *strings.Builder, at int, label, text string) {
	b.WriteString(pad(step))
	b.WriteString(label)
	if width := step + ansi.StringWidth(label); width+gap <= at {
		b.WriteString(pad(at - width))
	} else {
		b.WriteByte('\n')
		b.WriteString(pad(at))
	}
	for i, line := range wrap(text, pageW-at) {
		if i > 0 {
			b.WriteString(pad(at))
		}
		b.WriteString(line)
		b.WriteByte('\n')
	}
}

// indented writes running text as a block set in from the left edge.
func indented(b *strings.Builder, at int, text string, width int) {
	for _, line := range wrap(text, width) {
		b.WriteString(pad(at))
		b.WriteString(line)
		b.WriteByte('\n')
	}
}

// wrap breaks text into lines no wider than width, on spaces. A word longer
// than the whole column stands on its own line rather than being cut: it is a
// path or a flag, and half of either is worse than a line that runs long.
func wrap(text string, width int) []string {
	var out []string
	for para := range strings.SplitSeq(strings.TrimSpace(text), "\n") {
		line := ""
		for word := range strings.FieldsSeq(para) {
			switch {
			case line == "":
				line = word
			case ansi.StringWidth(line)+1+ansi.StringWidth(word) <= width:
				line += " " + word
			default:
				out = append(out, line)
				line = word
			}
		}
		out = append(out, line)
	}
	return out
}

func pad(n int) string { return strings.Repeat(" ", n) }

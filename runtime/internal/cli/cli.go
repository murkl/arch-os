// Package cli is the command line, read: one module, and everything it was
// given.
//
// Only half of a command line is known to this program. The runtime's own flags
// are compiled in; the rest is whatever the modules beside it declared, and
// there is no way to know what those are without loading them. So it is read
// twice — once for the two flags that say where the modules live, and once, in
// full, when they have been found.
//
// Nothing here knows what any flag means. It reads a line into names and values
// and hands them on; which variable a name answers, and what an answer does, is
// the module's business and stays in the module.
package cli

import (
	"fmt"
	"strings"

	"github.com/murkl/arch-os/runtime/internal/i18n"
	"github.com/murkl/arch-os/runtime/internal/spec"
)

// Command is a command line, read.
type Command struct {
	// Module is the module it named, or empty where it named none — which is
	// the question the interface then asks.
	Module string

	given map[string]string
}

// Has reports whether a flag was given at all.
func (c *Command) Has(name string) bool { _, ok := c.given[name]; return ok }

// Value is what a flag was given, or empty where it was not given at all.
func (c *Command) Value(name string) string { return c.given[name] }

// On reports whether a switch is on: given, and not given the word that turns
// it off. `--debug` and `--debug=true` are on, `--debug=false` is not.
func (c *Command) On(name string) bool {
	value, ok := c.given[name]
	return ok && value != spec.BoolFalse
}

// Parse reads a command line against the flags it may carry.
//
// The module may be written as a word or with the dashes an option would carry
// — `runtime installer` and `runtime --installer` are the same request — and it
// may stand anywhere, because a flag nobody declared is only read as a module
// while there is still no module. After that a name nobody knows is a mistake
// and is said to be one, rather than being carried into a run that quietly does
// something else.
func Parse(args []string, flags []spec.Flag) (*Command, error) {
	known := index(flags)
	c := &Command{given: map[string]string{}}
	for i := 0; i < len(args); i++ {
		name, value, attached, option, err := split(args[i])
		if err != nil {
			return nil, err
		}
		if !option {
			if c.Module != "" {
				return nil, fmt.Errorf("%s", i18n.T("One module at a time: %s or %s.", c.Module, name))
			}
			c.Module = name
			continue
		}
		f, ok := known[name]
		if !ok {
			// A word nobody declared, before anything has been opened, is what
			// to open. A value attached to it is not: `--x=y` is somebody
			// setting something, whatever they thought it was.
			if c.Module == "" && !attached {
				c.Module = name
				continue
			}
			return nil, unknown(name, flags)
		}
		switch {
		case f.Switch():
			// A switch never eats the word behind it, which is what keeps
			// `--debug installer` a module rather than a value.
			if !attached {
				value = spec.BoolTrue
			}
			if value != spec.BoolTrue && value != spec.BoolFalse {
				return nil, fmt.Errorf("%s", i18n.T("--%s is %s or %s, not %q.", name, spec.BoolTrue, spec.BoolFalse, value))
			}
		case attached:
		case i+1 < len(args):
			i++
			value = args[i]
		default:
			return nil, fmt.Errorf("%s", i18n.T("--%s takes a value.", name))
		}
		c.given[f.Name] = value
	}
	return c, nil
}

// Early reads the few flags that say where everything else is read from, before
// there is anything else to read.
//
// It knows only the flags it is handed and steps over every other word without
// touching the one behind it: a flag whose shape it cannot know is left exactly
// where it is rather than guessed at. Nothing is refused here either — a
// command line is judged once, in full, by Parse.
func Early(args []string, flags []spec.Flag) *Command {
	known := index(flags)
	c := &Command{given: map[string]string{}}
	for i := 0; i < len(args); i++ {
		name, value, attached, option, err := split(args[i])
		if !option || err != nil {
			continue
		}
		f, ok := known[name]
		if !ok {
			continue
		}
		switch {
		case f.Switch():
			if !attached {
				value = spec.BoolTrue
			}
		case !attached && i+1 < len(args):
			i++
			value = args[i]
		}
		c.given[f.Name] = value
	}
	return c
}

// split takes one argument apart: the name it carries, the value attached to it
// with an `=` if there is one, and whether it is written as an option at all.
//
// One dash or two is the same request. The long name is what a flag has here —
// there is no single-letter form to tell apart from a run of them — so `-conf`
// and `--conf` mean one thing and it costs nothing to accept both.
func split(arg string) (name, value string, attached, option bool, err error) {
	if !strings.HasPrefix(arg, "-") {
		return arg, "", false, false, nil
	}
	name, value, attached = strings.Cut(strings.TrimLeft(arg, "-"), "=")
	if name == "" {
		return "", "", false, false, fmt.Errorf("%s", i18n.T("%q names nothing.", arg))
	}
	return name, value, attached, true, nil
}

// index is every name a line may carry, including the aliases — a flag answers
// to both, and which of the two was typed makes no difference to anything past
// this point.
func index(flags []spec.Flag) map[string]spec.Flag {
	out := make(map[string]spec.Flag, len(flags))
	for _, f := range flags {
		out[f.Name] = f
		if f.Alias != "" {
			out[f.Alias] = f
		}
	}
	return out
}

// unknown is what a line that names something nobody declared is told, with
// everything that was on offer under it.
func unknown(name string, flags []spec.Flag) error {
	// The names, not the aliases: a list of what a line may carry is a list of
	// things to read, and the same flag under two names reads as two flags.
	names := make([]string, len(flags))
	for i, f := range flags {
		names[i] = "--" + f.Name
	}
	return fmt.Errorf("%s\n%s",
		i18n.T("No option called --%s.", name),
		i18n.T("This one takes %s.", strings.Join(names, ", ")))
}

// Union is every flag one command line may carry, each name appearing once.
//
// Two modules may well declare the same one — a switch that simulates a run is
// worth having in both — and on a line that has not named a module yet they are
// one flag, read the same way and carried by whichever module is opened. Two
// that disagree about whether it takes a value could not be read off one line at
// all, and are refused rather than resolved.
func Union(lists ...[]spec.Flag) ([]spec.Flag, error) {
	var out []spec.Flag
	seen := map[string]spec.Flag{}
	for _, list := range lists {
		for _, f := range list {
			was, ok := seen[f.Name]
			if !ok {
				seen[f.Name] = f
				out = append(out, f)
				continue
			}
			if was.Switch() != f.Switch() {
				return nil, fmt.Errorf("%s", i18n.T("--%s is a switch in one module and takes a value in another.", f.Name))
			}
		}
	}
	return out, nil
}

// Collide reports the first flag two of these lists both declare.
//
// The runtime's flags and a module's are declared in two places that cannot see
// each other — one compiled in, one read out of a folder — so this is the only
// place the two can be held against one another, and it is held at startup like
// every other authoring mistake.
func Collide(a, b []spec.Flag) string {
	seen := index(a)
	for _, f := range b {
		for _, name := range []string{f.Name, f.Alias} {
			if _, ok := seen[name]; ok && name != "" {
				return name
			}
		}
	}
	return ""
}

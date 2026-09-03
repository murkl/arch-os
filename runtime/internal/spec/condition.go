package spec

import (
	"fmt"
	"strings"

	"gopkg.in/yaml.v3"
)

// A condition is the whole of what one line of `conditions:` accepts: one
// variable, one operator, one value.
//
//	conditions: DESKTOP_ENABLED == true
//
//	conditions:
//	  - DESKTOP_ENABLED == true
//	  - GRAPHICS_DRIVER != none
//
// Deliberately not an expression language: three tokens cover every guard an
// installer needs, read as a sentence, and can be checked at load time against
// the variables actually declared — so a renamed variable is caught when the
// module is opened rather than by a task that silently never runs.
//
// Several are a list, and every one has to hold. There is no `or`: a row that
// belongs under two unrelated circumstances is two rows.
type condition struct {
	name  string
	equal bool
	want  string
}

func parseCondition(s string) (*condition, error) {
	f := strings.Fields(s)
	if len(f) != 3 || (f[1] != "==" && f[1] != "!=") {
		return nil, fmt.Errorf("bad condition %q, want `VAR == value` or `VAR != value`", s)
	}
	return &condition{name: f[0], equal: f[1] == "==", want: strings.Trim(f[2], `"'`)}, nil
}

func (c *condition) holds(get func(string) string) bool {
	return c.holdsFor(get(c.name))
}

// holdsFor is the same question asked about one value rather than about the
// answers as they stand, which is what lets a condition be reasoned about
// before anything has been answered — see Spec.implies.
func (c *condition) holdsFor(value string) bool { return (value == c.want) == c.equal }

// implies reports whether want necessarily holds wherever every condition in
// have does.
//
// Exact rather than approximate, and it can be: a variable that writes its
// values out has a domain small enough to decide the whole question over. Under
// `DESKTOP != none` a two-valued DESKTOP is gnome and nothing else, so a task
// guarded on `DESKTOP == gnome` runs wherever such a question is asked. Where
// the domain is open — a name typed into a box — only the same condition said
// again counts, which errs towards saying nothing rather than towards crying
// wolf about a module that is fine.
func (s *Module) implies(have []*condition, want *condition) bool {
	v := s.byName[want.name]
	if v == nil {
		return false
	}
	values := v.domain()
	if values == nil {
		for _, c := range have {
			if c.name != want.name {
				continue
			}
			// The same thing said again, or a value pinned to one thing, which
			// settles every other question about it.
			if *c == *want || (c.equal && !want.equal && c.want != want.want) {
				return true
			}
		}
		return false
	}
	// Every answer still open to the variable has to satisfy want. None left
	// open means the question is never asked at all, and anything holds there.
	for _, value := range values {
		if !allHold(have, want.name, value) {
			continue
		}
		if !want.holdsFor(value) {
			return false
		}
	}
	return true
}

// allHold reports whether every condition about one variable holds for one of
// its values. Conditions about anything else are somebody else's question.
func allHold(conds []*condition, name, value string) bool {
	for _, c := range conds {
		if c.name == name && !c.holdsFor(value) {
			return false
		}
	}
	return true
}

// holdAll reports whether every condition holds. No conditions always do.
func holdAll(conds []*condition, get func(string) string) bool {
	for _, c := range conds {
		if !c.holds(get) {
			return false
		}
	}
	return true
}

// Applies reports whether a task belongs in this run: every condition it
// declared holding.
func (t *Task) Applies(get func(string) string) bool { return holdAll(t.cond, get) }

// Applies reports whether a variable means anything given the answers so far.
// One that does not is neither asked for nor shown — a graphics driver is not a
// question on a machine that is not getting a desktop.
func (v *Variable) Applies(get func(string) string) bool { return holdAll(v.cond, get) }

// Conditions is `conditions:` as it may be written: one line, or a list of them.
//
// A scalar and a sequence for the same key is the one piece of yaml flexibility
// worth having here — the common case is a single guard and writing it as a
// one-item list would be ceremony, while the case that needs two must not have
// to be worked around.
type Conditions []string

func (c *Conditions) UnmarshalYAML(n *yaml.Node) error {
	switch n.Kind {
	case yaml.ScalarNode:
		var one string
		if err := n.Decode(&one); err != nil {
			return err
		}
		*c = Conditions{one}
		return nil
	case yaml.SequenceNode:
		var many []string
		if err := n.Decode(&many); err != nil {
			return err
		}
		*c = many
		return nil
	}
	return fmt.Errorf("line %d: conditions takes a condition or a list of them", n.Line)
}

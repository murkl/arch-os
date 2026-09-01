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
// tree is opened rather than by a task that silently never runs.
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
	return (get(c.name) == c.want) == c.equal
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

// inMode reports whether a row declaring this mode belongs in the run. Empty is
// every mode — the questions asked before the fork, which both sides of it are
// typed on.
func inMode(mode string, get func(string) string) bool {
	return mode == "" || mode == get(ModeVar)
}

// Applies reports whether a task belongs in this run: the right mode, which its
// stage settled, and every condition holding.
func (t *Task) Applies(get func(string) string) bool {
	return t.mode == get(ModeVar) && holdAll(t.cond, get)
}

// Applies reports whether a variable means anything given the answers so far.
// One that does not is neither asked for nor shown — a graphics driver is not a
// question on a machine that is not getting a desktop, and nothing about an
// installation is a question in a recovery.
func (v *Variable) Applies(get func(string) string) bool {
	return inMode(v.Mode, get) && holdAll(v.cond, get)
}

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

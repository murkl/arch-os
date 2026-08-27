package spec

import (
	"fmt"

	"gopkg.in/yaml.v3"
)

// Scalar is a yaml value read as text, whatever shape it was written in.
//
// Every answer this program carries is a string — it ends up in an environment
// variable, and there is nothing else it could be. But `default: true` and
// `default: 8` are how a person writes those, and refusing them would make the
// files read like a program's memory dump rather than a description of an
// installer.
type Scalar string

func (s *Scalar) UnmarshalYAML(n *yaml.Node) error {
	if n.Kind != yaml.ScalarNode {
		return fmt.Errorf("line %d: expected a single value", n.Line)
	}
	// The null literal is an absent value, not the word "null".
	if n.Tag == "!!null" {
		*s = ""
		return nil
	}
	*s = Scalar(n.Value)
	return nil
}

func (s Scalar) String() string { return string(s) }

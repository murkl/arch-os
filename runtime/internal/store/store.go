// Package store holds the answers: what every variable is set to right now, and
// the file they survive a restart in.
package store

import (
	"os"
	"slices"

	"github.com/murkl/arch-os/runtime/internal/exec"
	"github.com/murkl/arch-os/runtime/internal/i18n"
	"github.com/murkl/arch-os/runtime/internal/spec"
)

// Store is every declared variable and its current value.
//
// A value can come from five places, each beating the one before it: the
// declared default, the saved answer file, the command line, the preset
// somebody chose, and the answer somebody typed. That order is what lets a run
// with nobody in front of it be driven from one line, and a saved file stop the
// questions from being asked twice.
//
// The environment this program was started in is not among them. What a script
// is handed is settled here and given to it — a variable inherited from
// whatever shell happened to start this run is as often an accident as an
// instruction, and an installation is not a place to guess which.
type Store struct {
	mod   *spec.Module
	val   map[string]string
	facts map[string]string
	path  string // where the answers are written
}

// New builds a store from the folder's declarations, already carrying every
// default. path is the answer file, read by Load and written by Save.
func New(mod *spec.Module, path string) *Store {
	s := &Store{mod: mod, val: map[string]string{}, facts: map[string]string{}, path: path}
	for _, v := range mod.Vars {
		s.val[v.Name] = v.Default.String()
	}
	return s
}

// Path is the answer file this store reads and writes.
func (s *Store) Path() string { return s.path }

// Get reads a value. Runtime facts answer here too, so a script can find the
// folder it belongs to without anything having had to declare a variable
// nothing ever sets.
func (s *Store) Get(name string) string {
	if v, ok := s.val[name]; ok {
		return v
	}
	return s.facts[name]
}

// Set records an answer. It does not save — the caller decides when the file is
// written, because a value being tried out and a value being settled are not
// the same thing.
func (s *Store) Set(name, value string) { s.val[name] = value }

// SetFacts records what the run knows about itself. These are not variables —
// nothing declares them and nothing may prompt for them — but every script gets
// them, so a script can reach the folder it came from, its own log, and the
// answers it was given.
//
// What belongs to the module carries its name and what belongs to the runtime
// carries the runtime's, so a script never has to work out which of the two it
// is reading.
func (s *Store) SetFacts(version string) {
	s.facts[ModuleDirVar] = s.mod.Dir
	s.facts[ModuleConfVar] = s.path
	s.facts[VersionVar] = version
}

// The facts every script is handed, by name. A module reaches its own folder,
// its own answers and its own log through these, and the runtime's version
// through the last.
const (
	ModuleDirVar  = "MODULE_DIR"
	ModuleConfVar = "MODULE_CONF"
	ModuleLogVar  = "MODULE_LOG"
	VersionVar    = "RUNTIME_VERSION"
)

// SetFact records one further fact, for what is only known later — the log
// path, which exists once logging has opened it.
func (s *Store) SetFact(name, value string) { s.facts[name] = value }

// Env is what a script sees: the process environment, then every declared
// variable, then the runtime facts. Later entries win, so a variable always
// carries the value the store holds and never a stale inherited one.
//
// Secrets are in here like anything else — that is the whole reason they are
// asked for. They reach one bash process and go no further: not to the answer
// file, not to the log.
func (s *Store) Env() exec.Env {
	env := append(exec.Env{}, os.Environ()...)
	for _, v := range s.mod.Vars {
		env = append(env, v.Name+"="+s.val[v.Name])
	}
	env = append(env, spec.LangVar+"="+i18n.Current())
	for k, v := range s.facts {
		env = append(env, k+"="+v)
	}
	return env
}

// Apply takes the values of a chosen preset option. Nothing else about it
// survives being chosen: it is a set of answers, not a mode the installer stays
// in, so from here on every one of them is an ordinary value that can be
// changed.
func (s *Store) Apply(o *spec.PresetOption) {
	for name, value := range o.Values {
		s.val[name] = value.String()
	}
}

// Missing lists the questions still standing, in the order they were declared:
// every variable that is required, means something given the answers so far,
// and has no acceptable value yet.
//
// Two kinds are not among them, and for the same reason: there is no answering
// them yet, so leaving them in would be a machine that can never be finished
// answering. A secret is never written down and is asked for immediately before
// the run that needs it — see Secrets. A deferred value is one a task asks for
// mid-run, because until that task's turn there is nothing to choose from.
func (s *Store) Missing() []*spec.Variable {
	var out []*spec.Variable
	for _, v := range s.mod.Vars {
		if v.Secret() || v.Deferred() || !v.Applies(s.Get) {
			continue
		}
		if s.Invalid(v, s.val[v.Name]) != "" {
			out = append(out, v)
		}
	}
	return out
}

// Upfront lists the questions this module wants settled before anything else
// happens at all: before a network is joined, before the machine is checked,
// before a starting point is chosen.
//
// The same rule as Missing, narrowed — so a question already answered is not
// asked again on the way in, and a second start goes straight to the network.
func (s *Store) Upfront() []*spec.Variable {
	var out []*spec.Variable
	for _, v := range s.Missing() {
		if v.First {
			out = append(out, v)
		}
	}
	return out
}

// Secrets lists the variables that have to be typed before a run and are never
// kept — in declaration order, so a folder decides what is asked first.
//
// One this run was already given is not among them. A secret is asked for
// immediately before the run that needs it because there is nowhere to keep it,
// not because it has to be typed; a value handed in on the command line has
// been given, and asking again would be asking the same question twice.
func (s *Store) Secrets() []*spec.Variable {
	var out []*spec.Variable
	for _, v := range s.mod.Vars {
		if !v.Secret() || !v.Applies(s.Get) {
			continue
		}
		if value := s.val[v.Name]; value != "" && s.Invalid(v, value) == "" {
			continue
		}
		out = append(out, v)
	}
	return out
}

// Visible lists the variables worth showing on the settings page: everything
// that means something given the answers so far, in declaration order.
//
// A deferred value is not among them. It is a row nobody could answer from
// here — what it offers is read off work that has not happened yet — and a
// settings page is a promise that every row on it can be opened.
func (s *Store) Visible() []*spec.Variable {
	var out []*spec.Variable
	for _, v := range s.mod.Vars {
		if !v.Deferred() && v.Applies(s.Get) {
			out = append(out, v)
		}
	}
	return out
}

// Invalid returns why a value will not do, or "" if it will. The rules come
// from the declaration, so a value typed at a prompt and one edited straight
// into the answer file are held to exactly the same standard.
func (s *Store) Invalid(v *spec.Variable, value string) string {
	if value == "" {
		if v.Required {
			return v.Why()
		}
		return ""
	}
	switch {
	case v.Shape() == spec.TypeBool:
		if value != spec.BoolTrue && value != spec.BoolFalse {
			return v.Why()
		}
	case len(v.Values) > 0 && !slices.Contains(v.Values, value):
		return v.Why()
	}
	if !v.Matches(value) {
		return v.Why()
	}
	return ""
}

// Display is what a value looks like on a page: a secret as dots, a bool in
// words, and an unanswered question as a dash rather than as nothing at all —
// an empty column reads as a row that is still loading.
func (s *Store) Display(v *spec.Variable) string {
	value := s.val[v.Name]
	switch {
	case v.Secret():
		return i18n.T("asked just before the run")
	case value == "":
		return "—"
	}
	return Label(value)
}

// Label is how one value is read out loud: true and false in the interface's
// own language wherever they turn up, and every other value as itself.
//
// The two words are the runtime's rather than a folder's — they are what a
// script tests against, and what they are called on screen is not something a
// folder should have to translate — so a list that offers a third answer beside
// them still reads as Yes and No.
func Label(value string) string {
	switch value {
	case spec.BoolTrue:
		return i18n.T("Yes")
	case spec.BoolFalse:
		return i18n.T("No")
	}
	return value
}

// Forget drops every secret, so nothing is left in memory once the run that
// needed it is over.
func (s *Store) Forget() {
	for _, v := range s.mod.Vars {
		if v.Secret() {
			s.val[v.Name] = ""
		}
	}
}

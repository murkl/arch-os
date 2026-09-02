// Package store holds the answers: what every variable is set to right now, and
// the file they survive a restart in.
package store

import (
	"os"
	"slices"

	"installer/internal/exec"
	"installer/internal/i18n"
	"installer/internal/spec"
)

// Store is every declared variable and its current value.
//
// A value can come from five places, each beating the one before it: the
// declared default, the process environment, the saved answer file, the preset
// somebody chose, and the answer somebody typed. That order is what lets an
// exported variable drive an unattended run, and a saved file stop the
// questions from being asked twice.
type Store struct {
	spec  *spec.Spec
	val   map[string]string
	facts map[string]string
	path  string // where the answers are written
}

// New builds a store from the folder's declarations, already carrying every
// default. path is the answer file, read by Load and written by Save.
func New(sp *spec.Spec, path string) *Store {
	s := &Store{spec: sp, val: map[string]string{}, facts: map[string]string{}, path: path}
	for _, v := range sp.Vars {
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
func (s *Store) SetFacts(version string) {
	s.facts["INSTALLER_DIR"] = s.spec.Dir
	s.facts["INSTALLER_CONF"] = s.path
	s.facts["INSTALLER_VERSION"] = version
}

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
	for _, v := range s.spec.Vars {
		env = append(env, v.Name+"="+s.val[v.Name])
	}
	env = append(env, spec.LangVar+"="+i18n.Current())
	for k, v := range s.facts {
		env = append(env, k+"="+v)
	}
	return env
}

// LoadEnv takes any declared variable that is set in the process environment.
func (s *Store) LoadEnv() {
	for _, v := range s.spec.Vars {
		if v.Secret() {
			continue
		}
		if got, ok := os.LookupEnv(v.Name); ok && got != "" {
			s.val[v.Name] = got
		}
	}
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
	for _, v := range s.spec.Vars {
		if v.Secret() || v.Deferred() || !v.Applies(s.Get) {
			continue
		}
		if s.Invalid(v, s.val[v.Name]) != "" {
			out = append(out, v)
		}
	}
	return out
}

// Upfront lists the questions this tree wants settled before anything else
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
func (s *Store) Secrets() []*spec.Variable {
	var out []*spec.Variable
	for _, v := range s.spec.Vars {
		if v.Secret() && v.Applies(s.Get) {
			out = append(out, v)
		}
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
	for _, v := range s.spec.Vars {
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
	for _, v := range s.spec.Vars {
		if v.Secret() {
			s.val[v.Name] = ""
		}
	}
}

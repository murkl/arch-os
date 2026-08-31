package store

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"installer/internal/i18n"
	"installer/internal/spec"
)

// The answer file is shell, not yaml, and that is on purpose. It is the one
// file a person is most likely to open in an editor on a live medium with
// nothing installed on it, and `KEY='value' # what it is` is readable by
// everyone and sourceable by anything. It is also exactly the shape the
// variables reach a script in, so there is nothing to translate in either
// direction.

// Load reads the answer file over the values already held. A missing file is
// normal — it is what a first run looks like, and it is what makes the program
// ask rather than guess.
//
// A key nothing declares any more is passed over rather than refused: an
// installer folder gets edited, and a file written by an older one still has to
// open. A value that no longer satisfies its rules is kept exactly as written —
// it is not this function's place to decide, and Missing will put the question
// back where it belongs.
func (s *Store) Load() error {
	raw, err := os.ReadFile(s.path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	for line := range strings.SplitSeq(string(raw), "\n") {
		name, value, ok := parseLine(line)
		if !ok {
			continue
		}
		if slices.Contains(spec.RuntimeVars, name) {
			s.val[name] = value
			continue
		}
		v := s.spec.Var(name)
		if v == nil || v.Secret() {
			continue
		}
		s.val[name] = value
	}
	return nil
}

// Exists reports whether this machine has answered anything yet. It is the one
// question asked before the interface opens: an answer file is what turns a
// first run into a return.
func (s *Store) Exists() bool {
	_, err := os.Stat(s.path)
	return err == nil
}

// Save writes every answer worth keeping, in the order the folder declared
// them, each with its own description as a trailing comment — so the file reads
// as the same list of questions the interface asks, and a person editing it by
// hand can see what each line is for without a second document.
//
// Secrets are not written. Not masked, not empty-but-present: absent, so there
// is no line to wonder about.
func (s *Store) Save() error {
	if dir := filepath.Dir(s.path); dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	var b strings.Builder
	fmt.Fprintf(&b, "# %s\n", i18n.T("Answers given to %s. Edit by hand if you like.", s.spec.Name()))
	entry(&b, spec.LangVar, s.val[spec.LangVar], i18n.T("Interface language"))
	// Only where there was a choice: a tree that does one thing has a mode
	// nobody picked and a line saying so would be a question this file is
	// pretending was asked.
	if s.spec.Asked() {
		entry(&b, spec.ModeVar, s.val[spec.ModeVar], i18n.T("What this run does"))
	}
	group := ""
	for _, v := range s.spec.Vars {
		if v.Secret() {
			continue
		}
		if v.Group != group {
			group = v.Group
			if group != "" {
				fmt.Fprintf(&b, "\n# %s\n", i18n.T(group))
			}
		}
		// The title, not the description: a trailing comment is a label for the
		// line it sits on, and this file reads as a list of names and values.
		// What each one is for is a paragraph, and it is on the page that asks
		// the question.
		entry(&b, v.Name, s.val[v.Name], v.Label())
	}
	// Written whole and replaced in one step: a run interrupted mid-write must
	// not leave a half-file that reads as a machine having answered nothing.
	tmp := s.path + ".new"
	if err := os.WriteFile(tmp, []byte(b.String()), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, s.path)
}

// entry writes one line: the name, the value quoted so any character survives,
// and what the value is for.
func entry(b *strings.Builder, name, value, desc string) {
	fmt.Fprintf(b, "%s=%s", name, quote(value))
	if desc = strings.TrimSpace(desc); desc != "" {
		fmt.Fprintf(b, " # %s", desc)
	}
	b.WriteByte('\n')
}

// quote wraps a value in single quotes, the one shell quoting that has no
// escapes inside it: everything is literal until the next quote, and a quote
// itself is written by closing, escaping it, and opening again.
func quote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// parseLine reads one `KEY=value` line back, in the three shapes a person might
// have left it in: single-quoted, double-quoted, or bare. Anything else — a
// comment, a blank line, a line with no name in front of the equals — is not an
// answer and is passed over.
func parseLine(line string) (name, value string, ok bool) {
	line = strings.TrimSpace(line)
	if line == "" || strings.HasPrefix(line, "#") {
		return "", "", false
	}
	name, rest, found := strings.Cut(line, "=")
	name = strings.TrimSpace(name)
	if !found || name == "" {
		return "", "", false
	}
	rest = strings.TrimLeft(rest, " \t")
	switch {
	case strings.HasPrefix(rest, "'"):
		return name, unquoteSingle(rest[1:]), true
	case strings.HasPrefix(rest, `"`):
		value, _, _ = strings.Cut(rest[1:], `"`)
		return name, value, true
	}
	// Bare: the value runs to the first space, since anything after it is a
	// trailing comment or a second word nobody meant as part of the value.
	value, _, _ = strings.Cut(rest, " ")
	return name, strings.TrimSpace(value), true
}

// unquoteSingle reads a single-quoted shell string back, including the '\”
// dance that puts a quote inside one.
func unquoteSingle(s string) string {
	var b strings.Builder
	for {
		i := strings.IndexByte(s, '\'')
		if i < 0 {
			b.WriteString(s)
			return b.String()
		}
		b.WriteString(s[:i])
		rest := s[i+1:]
		if !strings.HasPrefix(rest, `\''`) {
			return b.String()
		}
		b.WriteByte('\'')
		s = rest[3:]
	}
}

// Package i18n translates the words the program shows.
//
// The source string is the key. A line of Go says T("Back") and a catalog
// answers with "Zurück"; a catalog that has nothing to say about it leaves the
// English standing. That is the whole mechanism, and it is chosen for two
// reasons: the code and the yaml stay readable on their own — nobody has to
// look up what ui.button.back renders as — and a missing translation degrades
// to the source language instead of to a key nobody can read.
//
// Two catalogs are merged at startup and behave as one: the runtime's own,
// compiled into the binary, and the installer tree's, which translates the
// words that tree wrote. Neither knows about the other.
package i18n

import (
	"fmt"
	"strings"

	"gopkg.in/yaml.v3"
)

// SourceLang is the language every msgid is written in. A catalog for it would
// be a file mapping each string to itself.
const SourceLang = "en"

// Catalog is one language: what it calls itself, and what it has to say.
type Catalog struct {
	// Language is the name in the language itself — "Deutsch", not "German".
	// A list of languages is read by the people who speak them.
	Language string            `yaml:"language"`
	Messages map[string]string `yaml:"messages"`
}

// Parse reads a catalog file.
func Parse(raw []byte) (*Catalog, error) {
	c := &Catalog{}
	if err := yaml.Unmarshal(raw, c); err != nil {
		return nil, err
	}
	return c, nil
}

// active is what is currently showing. Package state rather than a value passed
// down: every layer of the program says words, and threading a translator
// through all of them would put the argument in a hundred signatures to serve
// one process that only ever speaks one language at a time.
var (
	active = map[string]string{}
	lang   = SourceLang
)

// Use puts the program in a language, built from the catalogs given. Later
// catalogs win, so the installer tree can override a word the runtime also
// uses. Nil entries are skipped, which is what a language with no catalog on
// one side looks like.
func Use(code string, catalogs ...*Catalog) {
	lang = code
	active = map[string]string{}
	for _, c := range catalogs {
		if c == nil {
			continue
		}
		for k, v := range c.Messages {
			if v != "" {
				active[k] = v
			}
		}
	}
}

// Current is the code currently showing.
func Current() string { return lang }

// T translates, then formats. The arguments are applied after the lookup so a
// translation may move its placeholders — "%d of %d" and "%d von %d" are the
// same message, and a language that needs the numbers the other way round can
// write "%[2]d …".
func T(msg string, a ...any) string {
	out := msg
	if t, ok := active[msg]; ok {
		out = t
	}
	if len(a) == 0 {
		return out
	}
	return fmt.Sprintf(out, a...)
}

// Has reports whether the active language has something of its own to say about
// a message. Not the same question as whether T changes it: a word a language
// happens to spell exactly as English does — a product name, "Kernel" — is
// translated, and answering otherwise would send somebody looking for a gap
// that is not there.
func Has(msg string) bool {
	_, ok := active[msg]
	return ok
}

// Match picks the best available language for a locale as the environment
// writes it — "de_DE.UTF-8", "de", "C". The exact code wins, then the part in
// front of the underscore, so a de_AT machine gets the German catalog rather
// than falling back to English over a region nobody wrote a file for.
//
// Available is the set of codes on offer; an empty answer means none of them
// fits and the caller should stay on the source language.
func Match(locale string, available []string) string {
	locale = strings.ToLower(strings.TrimSpace(locale))
	if i := strings.IndexAny(locale, ".@"); i >= 0 {
		locale = locale[:i]
	}
	locale = strings.ReplaceAll(locale, "_", "-")
	if locale == "" || locale == "c" || locale == "posix" {
		return ""
	}
	for _, code := range available {
		if strings.EqualFold(code, locale) {
			return code
		}
	}
	base, _, _ := strings.Cut(locale, "-")
	for _, code := range available {
		if strings.EqualFold(code, base) {
			return code
		}
	}
	return ""
}

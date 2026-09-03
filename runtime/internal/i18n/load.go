package i18n

import (
	"io/fs"
	"path"
	"sort"
	"strings"
)

// Lang is one language on offer: the code it is selected by and the name it
// calls itself.
type Lang struct {
	Code string
	Name string
}

// Discover lists the languages the given sources hold, merged into one list.
//
// There are two sources and they are independent: the runtime's own catalogs,
// compiled into the binary, and each module's, which translate the
// words that module wrote. A language present in either is offered — a module
// may speak one the runtime has never heard of, and a half-translated interface
// is still worth more to the person who needs it than an English one.
//
// The source language always comes first; the rest follow by the name they call
// themselves, so the list reads the way a list of languages should.
func Discover(sources ...fs.FS) []Lang {
	names := map[string]string{SourceLang: "English"}
	for _, src := range sources {
		for code, c := range catalogs(src) {
			if c.Language != "" {
				names[code] = c.Language
			} else if _, ok := names[code]; !ok {
				names[code] = strings.ToUpper(code)
			}
		}
	}
	out := make([]Lang, 0, len(names))
	for code, name := range names {
		out = append(out, Lang{Code: code, Name: name})
	}
	sort.Slice(out, func(i, j int) bool {
		if (out[i].Code == SourceLang) != (out[j].Code == SourceLang) {
			return out[i].Code == SourceLang
		}
		return out[i].Name < out[j].Name
	})
	return out
}

// Activate puts the program in a language, reading that language's catalog from
// every source. Later sources win, so a module may reword something
// the runtime also says.
//
// A code with no catalog anywhere leaves every message at its source text,
// which is the right outcome: English is not a fallback here, it is what the
// messages are written in.
func Activate(code string, sources ...fs.FS) {
	found := make([]*Catalog, 0, len(sources))
	for _, src := range sources {
		if c := read(src, code); c != nil {
			found = append(found, c)
		}
	}
	Use(code, found...)
}

// catalogs reads every catalog in a source, keyed by language code. A source
// that is not there — a module with no locales at all — is simply
// empty, not an error: translations are an addition, never a requirement.
func catalogs(src fs.FS) map[string]*Catalog {
	out := map[string]*Catalog{}
	if src == nil {
		return out
	}
	entries, err := fs.ReadDir(src, ".")
	if err != nil {
		return out
	}
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || path.Ext(name) != Ext {
			continue
		}
		code := strings.TrimSuffix(name, Ext)
		if c := read(src, code); c != nil {
			out[code] = c
		}
	}
	return out
}

// read loads one language's catalog from a source. Anything unreadable or
// malformed is treated as absent: a broken translation must never be the reason
// an installer will not start.
func read(src fs.FS, code string) *Catalog {
	if src == nil || code == "" {
		return nil
	}
	raw, err := fs.ReadFile(src, code+Ext)
	if err != nil {
		return nil
	}
	c, err := Parse(raw)
	if err != nil {
		return nil
	}
	return c
}

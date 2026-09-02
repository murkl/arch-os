package i18n

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"regexp"
	"strconv"
	"strings"
)

// Ext is what a catalog file is called: the language code, and this. The
// template they are filled in from sits in the same folder and ends in .pot,
// and it is skipped by exactly that difference — it is a list to work through,
// not a language anybody speaks.
const Ext = ".po"

// LanguageName is the message whose translation is a language's own name for
// itself — "Deutsch" in de.po, "Français" in fr.po. Every catalog carries it,
// which is how a list of languages can be read by the people who speak them
// without this program keeping a table of language names for a world it has not
// been translated into yet.
const LanguageName = "English"

// Parse reads a catalog: a po file as gettext writes one, and as a translation
// platform hands one back.
//
// Only what this program can act on is read. A fuzzy entry is skipped, which is
// what the flag is for — the source text changed under a translation, and the
// English is the better of the two until somebody has looked. Contexts and
// plural forms are skipped rather than guessed at: nothing here writes them, so
// an entry carrying one was written by something that knows more than this does.
func Parse(raw []byte) (*Catalog, error) {
	c := &Catalog{Messages: map[string]string{}}
	var (
		id, str  strings.Builder
		into     *strings.Builder
		started  bool // an entry is being read
		fuzzy    bool
		unusable bool
	)
	flush := func() {
		// The header is the entry with no source text, and an empty translation
		// is one nobody has written yet. Neither is a message.
		if k, v := id.String(), str.String(); started && !fuzzy && !unusable && k != "" && v != "" {
			c.Messages[k] = v
		}
		id.Reset()
		str.Reset()
		into, started, fuzzy, unusable = nil, false, false, false
	}

	sc := bufio.NewScanner(bytes.NewReader(raw))
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for n := 1; sc.Scan(); n++ {
		line := strings.TrimSpace(sc.Text())
		if line == "" {
			flush()
			continue
		}
		// Comments, references and flags — and among the flags the one that
		// decides whether the entry under it may be shown at all. An obsolete
		// entry starts with #~ and is a comment like any other.
		if line[0] == '#' {
			if strings.HasPrefix(line, "#,") && hasFlag(line, "fuzzy") {
				fuzzy = true
			}
			continue
		}
		switch {
		case strings.HasPrefix(line, "msgctxt"),
			strings.HasPrefix(line, "msgid_plural"),
			strings.HasPrefix(line, "msgstr["):
			unusable, into = true, nil
			continue
		case strings.HasPrefix(line, "msgid"):
			// An entry that follows without a blank line between them.
			if started {
				flush()
			}
			started, into = true, &id
			line = strings.TrimSpace(line[len("msgid"):])
		case strings.HasPrefix(line, "msgstr"):
			into = &str
			line = strings.TrimSpace(line[len("msgstr"):])
		case line[0] != '"':
			return nil, fmt.Errorf("line %d: %s", n, line)
		}
		if into == nil {
			continue
		}
		text, err := strconv.Unquote(line)
		if err != nil {
			return nil, fmt.Errorf("line %d: %s", n, line)
		}
		into.WriteString(text)
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	flush()

	c.Language = c.Messages[LanguageName]
	return c, nil
}

// hasFlag reports whether a #, line carries one flag, whatever else is on it.
func hasFlag(line, want string) bool {
	for _, f := range strings.Split(strings.TrimPrefix(line, "#,"), ",") {
		if strings.TrimSpace(f) == want {
			return true
		}
	}
	return false
}

// Entry is one message on its way into a template: what it says, what it is,
// and where it was found.
type Entry struct {
	Text string
	Note string   // what this is, for whoever translates it without seeing it in place
	Refs []string // where it comes from, as a translator would go looking for it
}

// Template writes a pot: every message a program says, each with its
// translation left empty. It is what a catalog for a new language is started
// from, and what an existing one is brought up to date against — see msgmerge.
//
// The header carries no POT-Creation-Date on purpose. A template that changed
// every time it was written would be a diff on every build, and there would be
// no way to ask whether it is still current.
func Template(w io.Writer, project string, entries []Entry) error {
	b := bufio.NewWriter(w)

	fmt.Fprintf(b, "# Translation template for %s.\n", project)
	fmt.Fprint(b, "#\n")
	fmt.Fprint(b, "# One catalog per language beside this file, named by its code: de.po, fr.po.\n")
	fmt.Fprint(b, "# The msgid is the English source text and the key at once, so a message no\n")
	fmt.Fprint(b, "# catalog has anything to say about is shown exactly as it stands here — which\n")
	fmt.Fprint(b, "# is what makes a half-finished translation useful from its first line.\n")
	fmt.Fprint(b, "#\n")
	fmt.Fprint(b, "# Generated. See the Makefile.\n")
	fmt.Fprint(b, "msgid \"\"\n")
	fmt.Fprint(b, "msgstr \"\"\n")
	fmt.Fprintf(b, "\"Project-Id-Version: %s\\n\"\n", project)
	fmt.Fprint(b, "\"MIME-Version: 1.0\\n\"\n")
	fmt.Fprint(b, "\"Content-Type: text/plain; charset=UTF-8\\n\"\n")
	fmt.Fprint(b, "\"Content-Transfer-Encoding: 8bit\\n\"\n")

	all := append([]Entry{{
		Text: LanguageName,
		Note: `the name of this language in the language itself — "Deutsch", not "German". A list of languages is read by the people who speak them.`,
	}}, entries...)

	for _, e := range all {
		fmt.Fprintln(b)
		for _, line := range wrap("#. ", e.Note) {
			fmt.Fprintln(b, line)
		}
		if len(e.Refs) > 0 {
			fmt.Fprintf(b, "#: %s\n", strings.Join(e.Refs, " "))
		}
		// What a translation is checked against: a placeholder dropped or
		// renamed on the way into another language is a message that breaks
		// where it is printed, not where it was written.
		if placeholder.MatchString(e.Text) {
			fmt.Fprint(b, "#, c-format\n")
		}
		writeString(b, "msgid", e.Text)
		writeString(b, "msgstr", "")
	}
	return b.Flush()
}

// placeholder matches a printf verb, which is what makes an entry c-format.
// Neither %% nor a per cent sign with a word behind it is one — "100% of the
// disk" is a sentence, and flagging it would have a translation refused over an
// argument that was never there.
var placeholder = regexp.MustCompile(`%[-+#0]*\[?[0-9]*]?(\.[0-9]+)?[a-zA-Z]`)

// writeString writes one msgid or msgstr, as a block where the text runs over
// several lines. A paragraph read as one long escaped line is a paragraph
// nobody proofreads.
func writeString(w io.Writer, keyword, s string) {
	if !strings.Contains(s, "\n") {
		fmt.Fprintf(w, "%s %s\n", keyword, strconv.Quote(s))
		return
	}
	fmt.Fprintf(w, "%s \"\"\n", keyword)
	for _, line := range strings.SplitAfter(s, "\n") {
		if line != "" {
			fmt.Fprintln(w, strconv.Quote(line))
		}
	}
}

// wrap turns a note into comment lines short enough to read in a diff. Empty in,
// nothing out.
func wrap(prefix, note string) []string {
	const width = 76
	if note = strings.TrimSpace(note); note == "" {
		return nil
	}
	var out []string
	line := prefix
	for _, word := range strings.Fields(note) {
		if len(line) > len(prefix) && len(line)+1+len(word) > width {
			out = append(out, line)
			line = prefix
		}
		if len(line) > len(prefix) {
			line += " "
		}
		line += word
	}
	return append(out, line)
}

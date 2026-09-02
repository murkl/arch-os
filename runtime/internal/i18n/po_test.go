package i18n

import (
	"strings"
	"testing"
)

// The flag says the source text moved out from under the translation. English
// is the better of the two until somebody has looked at it.
func TestAFuzzyEntryIsNotShown(t *testing.T) {
	c, err := Parse([]byte(`
msgid "Back"
msgstr "Zurück"

#, fuzzy, c-format
msgid "%d of %d"
msgstr "%d von %d"
`))
	if err != nil {
		t.Fatal(err)
	}
	if c.Messages["Back"] != "Zurück" {
		t.Errorf("Back = %q", c.Messages["Back"])
	}
	if got, ok := c.Messages["%d of %d"]; ok {
		t.Errorf("the fuzzy entry was read as %q", got)
	}
}

// A paragraph is written as one block of lines and read back as one string.
func TestAMessageOverSeveralLinesIsOneMessage(t *testing.T) {
	c, err := Parse([]byte(`
msgid ""
"Arch OS is installed\n"
"\n"
"Everything from here on is offered."
msgstr ""
"Arch OS ist installiert\n"
"\n"
"Alles Weitere ist ein Angebot."
`))
	if err != nil {
		t.Fatal(err)
	}
	want := "Arch OS ist installiert\n\nAlles Weitere ist ein Angebot."
	if got := c.Messages["Arch OS is installed\n\nEverything from here on is offered."]; got != want {
		t.Errorf("= %q, want %q", got, want)
	}
}

// The header is not a message, and neither is an entry nobody has got to yet.
func TestTheHeaderAndTheEmptyEntriesAreNotMessages(t *testing.T) {
	c, err := Parse([]byte(`
msgid ""
msgstr ""
"Language: de\n"

msgid "Back"
msgstr ""
`))
	if err != nil {
		t.Fatal(err)
	}
	if len(c.Messages) != 0 {
		t.Errorf("Messages = %v, want none", c.Messages)
	}
}

// Nothing here writes a context or a plural, so an entry carrying one came from
// somewhere that knows something this does not — and is left alone rather than
// half read.
func TestAnEntryWithAContextIsSkipped(t *testing.T) {
	c, err := Parse([]byte(`
msgctxt "menu"
msgid "Open"
msgstr "Öffnen"

msgid "Back"
msgstr "Zurück"
`))
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := c.Messages["Open"]; ok {
		t.Error("the entry with a context was read")
	}
	if c.Messages["Back"] != "Zurück" {
		t.Errorf("the entry after it was lost: %v", c.Messages)
	}
}

// An entry msgmerge left behind is a comment, and comments are not messages.
func TestAnObsoleteEntryIsAComment(t *testing.T) {
	c, err := Parse([]byte(`
#~ msgid "Gone"
#~ msgstr "Weg"
`))
	if err != nil {
		t.Fatal(err)
	}
	if len(c.Messages) != 0 {
		t.Errorf("Messages = %v, want none", c.Messages)
	}
}

// The name of a language is the translation of one message, so a catalog names
// itself the same way it says everything else.
func TestACatalogNamesItsOwnLanguage(t *testing.T) {
	c, err := Parse([]byte("msgid \"" + LanguageName + "\"\nmsgstr \"Deutsch\"\n"))
	if err != nil {
		t.Fatal(err)
	}
	if c.Language != "Deutsch" {
		t.Errorf("Language = %q", c.Language)
	}
}

func TestALineThatIsNoPoIsAnError(t *testing.T) {
	if _, err := Parse([]byte("msgid \"Back\"\nZurück\n")); err == nil {
		t.Error("Parse accepted a line that is not po")
	}
}

// Everything a program says, with the translations left empty: what a catalog
// for a new language is started from.
func TestATemplateHoldsEveryMessageAndNoTranslations(t *testing.T) {
	var b strings.Builder
	err := Template(&b, "installer", []Entry{
		{Text: "Host name", Note: "the question", Refs: []string{"installer.yaml"}},
		{Text: "%d of %d done", Refs: []string{"tui/run.go:12"}},
		{Text: "First line.\n\nSecond line."},
	})
	if err != nil {
		t.Fatal(err)
	}
	out := b.String()
	for _, want := range []string{
		"\"Project-Id-Version: installer\\n\"",
		"#. the question",
		"#: installer.yaml",
		"msgid \"Host name\"",
		// A placeholder is what a translation is checked against.
		"#, c-format\nmsgid \"%d of %d done\"",
		// A paragraph is written as lines, so it can be read as lines.
		"msgid \"\"\n\"First line.\\n\"\n\"\\n\"\n\"Second line.\"",
		// Every catalog carries the name of its own language.
		"msgid \"" + LanguageName + "\"",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("the template has no %q in it:\n%s", want, out)
		}
	}
	if strings.Contains(out, "POT-Creation-Date") {
		t.Error("the template carries a date, so it changes when its strings have not")
	}

	c, err := Parse([]byte(out))
	if err != nil {
		t.Fatalf("the template is not readable po: %v\n%s", err, out)
	}
	if len(c.Messages) != 0 {
		t.Errorf("the template holds translations: %v", c.Messages)
	}
}

// A per cent sign that is not a placeholder must not be flagged, or a
// translation gets refused for something that was never an argument.
func TestOnlyRealPlaceholdersMakeAnEntryCFormat(t *testing.T) {
	for text, want := range map[string]bool{
		"%s is ready":      true,
		"%d of %d":         true,
		"100% of the disk": false,
		"Back":             false,
	} {
		var b strings.Builder
		if err := Template(&b, "test", []Entry{{Text: text}}); err != nil {
			t.Fatal(err)
		}
		if got := strings.Contains(b.String(), "#, c-format"); got != want {
			t.Errorf("%q: c-format = %v, want %v", text, got, want)
		}
	}
}

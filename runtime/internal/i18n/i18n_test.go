package i18n

import (
	"strconv"
	"strings"
	"testing"
	"testing/fstest"
)

// catalog is a po file as a translation platform hands one back, minus
// everything a running program has no use for.
func catalog(language string, messages map[string]string) []byte {
	var b strings.Builder
	b.WriteString("msgid \"\"\nmsgstr \"\"\n\"Content-Type: text/plain; charset=UTF-8\\n\"\n")
	entry := func(k, v string) {
		b.WriteString("\nmsgid " + strconv.Quote(k) + "\nmsgstr " + strconv.Quote(v) + "\n")
	}
	if language != "" {
		entry(LanguageName, language)
	}
	for k, v := range messages {
		entry(k, v)
	}
	return []byte(b.String())
}

// The source string is the key, and a message nothing has to say about stays
// exactly as it is written in the code. That is what makes a half-finished
// catalog useful from its first line.
func TestAnUntranslatedMessageStaysAsWritten(t *testing.T) {
	Use("de", &Catalog{Messages: map[string]string{"Back": "Zurück"}})
	if got := T("Back"); got != "Zurück" {
		t.Errorf("T(Back) = %q", got)
	}
	if got := T("Something nobody translated"); got != "Something nobody translated" {
		t.Errorf("T(untranslated) = %q", got)
	}
}

// The arguments are applied after the lookup, so a translation may move its
// placeholders.
func TestFormattingHappensAfterTheLookup(t *testing.T) {
	Use("de", &Catalog{Messages: map[string]string{"%d of %d": "%d von %d"}})
	if got := T("%d of %d", 3, 12); got != "3 von 12" {
		t.Errorf("T = %q", got)
	}
}

func TestHasIsAboutTheCatalogNotTheOutput(t *testing.T) {
	Use("de", &Catalog{Messages: map[string]string{"Kernel": "Kernel", "Back": "Zurück"}})
	// A word a language spells exactly as English does is still translated.
	if !Has("Kernel") {
		t.Error("Has(Kernel) = false, want true — it is in the catalog")
	}
	if Has("Missing") {
		t.Error("Has(Missing) = true")
	}
}

// Two independent sources, merged. The folder's catalog is laid over the
// runtime's, so a folder may reword something the runtime also says.
func TestTheFolderCatalogWinsOverTheRuntimeOne(t *testing.T) {
	runtime := fstest.MapFS{"de.po": {Data: catalog("Deutsch", map[string]string{
		"Back": "Zurück", "Install": "Installieren",
	})}}
	folder := fstest.MapFS{"de.po": {Data: catalog("Deutsch", map[string]string{
		"Install": "Einspielen", "Disk": "Datenträger",
	})}}
	Activate("de", runtime, folder)
	for msg, want := range map[string]string{
		"Back":    "Zurück",      // only the runtime says it
		"Install": "Einspielen",  // both do, and the folder wins
		"Disk":    "Datenträger", // only the folder says it
	} {
		if got := T(msg); got != want {
			t.Errorf("T(%q) = %q, want %q", msg, got, want)
		}
	}
}

func TestActivatingALanguageNobodyHasLeavesTheSourceText(t *testing.T) {
	Activate("fr", fstest.MapFS{"de.po": {Data: catalog("Deutsch", map[string]string{"Back": "Zurück"})}})
	if got := T("Back"); got != "Back" {
		t.Errorf("T(Back) = %q, want the source text", got)
	}
	if Current() != "fr" {
		t.Errorf("Current() = %q", Current())
	}
}

// A broken translation must never be the reason an installer will not start.
func TestABrokenCatalogIsIgnoredRatherThanFatal(t *testing.T) {
	src := fstest.MapFS{"de.po": {Data: []byte("msgid \"Back\"\nthis is not a po file\n")}}
	Activate("de", src)
	if got := T("Back"); got != "Back" {
		t.Errorf("T(Back) = %q", got)
	}
	if got := Discover(src); len(got) != 1 || got[0].Code != SourceLang {
		t.Errorf("Discover = %+v, want only the source language", got)
	}
}

func TestDiscoverListsTheSourceLanguageFirst(t *testing.T) {
	src := fstest.MapFS{
		"de.po": {Data: catalog("Deutsch", nil)},
		"fr.po": {Data: catalog("Français", nil)},
		"es.po": {Data: catalog("Español", nil)},
		"notes": {Data: []byte("not a catalog")},
		// The template is what catalogs are filled in from, not a language.
		"archos.pot": {Data: catalog("", map[string]string{"Back": ""})},
	}
	got := Discover(src)
	var codes, names []string
	for _, l := range got {
		codes = append(codes, l.Code)
		names = append(names, l.Name)
	}
	// Source first, then by the name each language calls itself.
	if strings.Join(codes, ",") != "en,de,es,fr" {
		t.Errorf("codes = %v", codes)
	}
	if names[0] != "English" || names[1] != "Deutsch" {
		t.Errorf("names = %v", names)
	}
}

func TestMatchPrefersTheExactLocaleThenTheLanguage(t *testing.T) {
	available := []string{"en", "de", "pt-BR"}
	for _, tc := range []struct{ locale, want string }{
		{"de_DE.UTF-8", "de"},
		{"de", "de"},
		{"de_AT", "de"},
		{"pt_BR.UTF-8", "pt-BR"},
		{"pt_PT", ""}, // no plain pt catalog, and pt-BR is not it
		{"fr_FR.UTF-8", ""},
		{"C", ""},
		{"POSIX", ""},
		{"", ""},
	} {
		if got := Match(tc.locale, available); got != tc.want {
			t.Errorf("Match(%q) = %q, want %q", tc.locale, got, tc.want)
		}
	}
}

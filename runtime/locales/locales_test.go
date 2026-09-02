package locales_test

import (
	"strings"
	"testing"

	"installer/internal/i18n"
	"installer/locales"
)

// The catalogs that actually ship, which no other test looks at — everything
// else builds its own. A file that stopped parsing, or stopped being filled in,
// would leave the interface in English with nothing on screen to say why.
func TestEveryCatalogThatShipsHoldsALanguage(t *testing.T) {
	langs := i18n.Discover(locales.FS)
	if len(langs) < 2 {
		t.Fatalf("Discover = %v, want the source language and at least one catalog", langs)
	}
	for _, l := range langs {
		if l.Code == i18n.SourceLang {
			continue
		}
		raw, err := locales.FS.ReadFile(l.Code + i18n.Ext)
		if err != nil {
			t.Fatal(err)
		}
		c, err := i18n.Parse(raw)
		if err != nil {
			t.Fatalf("%s: %v", l.Code, err)
		}
		if len(c.Messages) == 0 {
			t.Errorf("%s translates nothing", l.Code)
		}
		// A language is listed in its own words or not at all: the fallback is
		// the code in capitals, which is nobody's name for their language.
		if c.Language == "" || c.Language == strings.ToUpper(l.Code) {
			t.Errorf("%s does not name its own language: %q", l.Code, c.Language)
		}
	}
}

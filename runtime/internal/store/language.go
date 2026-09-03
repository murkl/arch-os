package store

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/murkl/arch-os/runtime/internal/i18n"
	"github.com/murkl/arch-os/runtime/internal/spec"
)

// Language is the one answer that belongs to the runtime rather than to any of
// its modules: the words all of them are read in.
//
// It cannot live in a module's answer file, because it is settled before a
// module has been chosen — and it should not be asked twice on a machine that
// has already said so. So it is kept beside them, in a file of the same shape
// and read the same way, holding the one thing that is not a module's business.
type Language struct {
	path string
	code string
}

// NewLanguage reads the runtime's own answers, or comes back empty where there
// are none — which is what a first run looks like.
func NewLanguage(path string) *Language {
	l := &Language{path: path}
	raw, err := os.ReadFile(path)
	if err != nil {
		return l
	}
	for line := range strings.SplitSeq(string(raw), "\n") {
		if name, value, ok := parseLine(line); ok && name == spec.LangVar {
			l.code = value
		}
	}
	return l
}

// Code is the language settled last time, empty where none was.
func (l *Language) Code() string { return l.code }

// Set records a language. It does not save — the caller decides when the file
// is written.
func (l *Language) Set(code string) { l.code = code }

// Save writes the runtime's answers, whole and in one step, the way a module's
// are written.
func (l *Language) Save() error {
	if dir := filepath.Dir(l.path); dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	var b strings.Builder
	fmt.Fprintf(&b, "# %s\n", i18n.T("Answers the runtime keeps for every module. Edit by hand if you like."))
	entry(&b, spec.LangVar, l.code, i18n.T("Interface language"))
	tmp := l.path + ".new"
	if err := os.WriteFile(tmp, []byte(b.String()), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, l.path)
}

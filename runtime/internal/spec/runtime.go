package spec

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"

	"github.com/murkl/arch-os/runtime/internal/i18n"
)

// FileRuntime is the one yaml beside the binary that is not a module.
//
// It has a reserved name because it is what the binary reads to know what it
// is: everything a run needs before a module has been chosen — the product's
// name, its wordmark, its one colour — and the list of modules it offers.
const FileRuntime = "runtime.yaml"

// Runtime is the whole of what a binary and the folders beside it add up to.
//
// It is what no module can answer for itself. An installer and a recovery of
// one product are two programs and one product — the same wordmark on the way
// in, the same colour on every page, the same name over the question of which
// of them to open — and a module that declared any of that would be declaring
// it for its neighbours as well.
//
// It is also the whole of what makes this binary *this* product rather than
// another one. Nothing about Arch Linux is compiled in: a different name, a
// different colour and a different list of modules is a different product, out
// of the same binary.
type Runtime struct {
	// Name is the product, over the page that asks which of its modules to
	// open. Not translated: it is a name, and the same one in every language.
	Name string `yaml:"name"`

	// Accent is the one colour everything on screen is built from, #rrggbb, and
	// Logo the wordmark the interface comes up out of — everything above the
	// first blank line a dim eyebrow over it.
	Accent string `yaml:"accent"`
	Logo   string `yaml:"logo"`

	// Modules is what this runtime offers, in the order it offers them. Each is
	// a folder beside this file, holding that module's own declaration.
	//
	// Written out rather than discovered: the list is what a person adds a
	// module to and takes one out of, it is the order they are offered in, and
	// it is what the command line is checked against. A folder that is not on it
	// is not part of this product.
	Modules []string `yaml:"modules"`

	// Where this was read: the file itself, and the folder every module of it
	// sits in.
	File string `yaml:"-"`
	Dir  string `yaml:"-"`
}

// LoadRuntime reads the declaration beside the binary, or in the folder named
// outright, and checks over everything it says about itself.
//
// It is required. A binary with no runtime.yaml beside it is not a product yet:
// it has no name, no colours and nothing to offer, and saying so at startup is
// better than coming up blank.
func LoadRuntime(explicit string) (*Runtime, error) {
	dir, err := root(explicit)
	if err != nil {
		return nil, err
	}
	path := filepath.Join(dir, FileRuntime)
	var r Runtime
	if err := read(path, &r); err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("%s\n%s",
				i18n.T("Nothing to run here."),
				i18n.T("A %s file has to sit next to this program, in %s.", FileRuntime, dir))
		}
		return nil, err
	}
	r.File, r.Dir = path, dir
	return &r, r.check()
}

func (r *Runtime) check() error {
	if r.Accent != "" && !hexColor.MatchString(r.Accent) {
		return fmt.Errorf("%s: accent must be #rrggbb, got %q", FileRuntime, r.Accent)
	}
	if len(r.Modules) == 0 {
		return fmt.Errorf("%s: no modules", FileRuntime)
	}
	seen := map[string]bool{}
	for _, id := range r.Modules {
		switch {
		case id == "" || filepath.Base(id) != id || id == "." || id == "..":
			return fmt.Errorf("%s: %q is not a folder name", FileRuntime, id)
		case seen[id]:
			return fmt.Errorf("%s: module %s is listed twice", FileRuntime, id)
		}
		seen[id] = true
	}
	return nil
}

// Has reports whether id is one of the modules this runtime offers. It is what
// a name given on the command line is held against, so adding a module is a
// line of yaml and a folder rather than anything compiled in.
func (r *Runtime) Has(id string) bool { return slices.Contains(r.Modules, id) }

// Path is where a module's folder is.
func (r *Runtime) Path(id string) string { return filepath.Join(r.Dir, id) }

// root is where a run looks for everything it was shipped with: the folder
// named outright, or the one the binary is in.
func root(explicit string) (string, error) {
	dir := explicit
	if dir == "" {
		dir = binaryDir()
	}
	return filepath.Abs(dir)
}

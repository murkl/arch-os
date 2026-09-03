package spec

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/murkl/arch-os/runtime/internal/i18n"
)

// FileRuntime is the one yaml beside the binary that is not a module, and
// DirModules the folder beside it that holds them.
//
// Both have reserved names because they are what the binary reads to know what
// it is: everything a run needs before a module has been chosen — the product's
// name, its wordmark, its one colour — and the modules it offers.
const (
	FileRuntime = "runtime.yaml"
	DirModules  = "modules"
)

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
// different colour and a different folder of modules is a different product,
// out of the same binary.
type Runtime struct {
	// Name is the product, over the page that asks which of its modules to
	// open. Not translated: it is a name, and the same one in every language.
	Name string `yaml:"name"`

	// Accent is the one colour everything on screen is built from, #rrggbb, and
	// Logo the wordmark the interface comes up out of — everything above the
	// first blank line a dim eyebrow over it.
	Accent string `yaml:"accent"`
	Logo   string `yaml:"logo"`

	// Help is what --help says about the product as a whole. What each module
	// takes is read out of the module, so nothing here has to be kept in step
	// with it.
	Help Help `yaml:"help"`

	// Modules is what this runtime offers, in the order it offers them: the
	// folders in DirModules, by name.
	//
	// Read off the filesystem rather than written down here, because a list
	// beside the folders is a second copy of them that can disagree. Adding a
	// module is a folder and taking one away is deleting it, and what each of
	// them is called on the page that offers it is in its own declaration.
	Modules []string `yaml:"-"`

	// Where this was read: the file itself, and the folder its modules sit in.
	File string `yaml:"-"`
	Dir  string `yaml:"-"`
}

// Help is the page a run puts up when it is asked what it is rather than told
// what to do.
//
// The runtime writes the page; this is the part of it only the product can
// answer for — what it is for, what it is typed as, and the handful of whole
// command lines worth copying. Everything else on that page is read off the
// modules and off the runtime's own flags, so a product that gains a module
// gains a line here without anybody editing one.
type Help struct {
	// About is the sentence under the name: what this product is for, over the
	// list of what it offers.
	About string `yaml:"about"`

	// Command is what to type. Empty is the name the binary was started by,
	// which is right everywhere except on a machine that reaches it through a
	// launcher of another name.
	Command string `yaml:"command"`

	// Examples are whole command lines worth copying, each with what it does
	// under it. Two or three: a help page nobody reads to the end has failed at
	// the one job it has.
	Examples []Example `yaml:"examples"`
}

// Example is one command line and what it does.
type Example struct {
	Run   string `yaml:"run"`
	About string `yaml:"about"`
}

// LoadRuntime reads the declaration beside the binary, or in the folder named
// outright, and finds the modules next to it.
//
// Both are required. A binary with no runtime.yaml beside it is not a product
// yet: it has no name, no colours and nothing to offer, and saying so at
// startup is better than coming up blank.
func LoadRuntime(explicit string) (*Runtime, error) {
	dir, err := root(explicit)
	if err != nil {
		return nil, err
	}
	path := filepath.Join(dir, FileRuntime)
	var r Runtime
	if err := read(path, &r); err != nil {
		if os.IsNotExist(err) {
			return nil, missing(i18n.T("A %s file has to sit next to this program, in %s.", FileRuntime, dir))
		}
		return nil, err
	}
	r.File, r.Dir = path, dir
	r.Help.About = reflow(r.Help.About)
	for i := range r.Help.Examples {
		r.Help.Examples[i].About = reflow(r.Help.Examples[i].About)
	}
	if err := r.check(); err != nil {
		return nil, err
	}
	if r.Modules, err = discover(filepath.Join(dir, DirModules)); err != nil {
		return nil, err
	}
	return &r, nil
}

func (r *Runtime) check() error {
	if r.Accent != "" && !hexColor.MatchString(r.Accent) {
		return fmt.Errorf("%s: accent must be #rrggbb, got %q", FileRuntime, r.Accent)
	}
	return nil
}

// discover is the modules in a folder, in name order — which is the order they
// are offered in. Every folder in it is one; whether it holds something that
// loads is decided by loading it, so a broken module is a startup error rather
// than a row quietly missing from the page.
func discover(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil && !os.IsNotExist(err) {
		return nil, err
	}
	var out []string
	for _, entry := range entries {
		if entry.IsDir() {
			out = append(out, entry.Name())
		}
	}
	if len(out) == 0 {
		return nil, missing(i18n.T("A %s folder with something in it has to sit next to this program, in %s.", DirModules, filepath.Dir(dir)))
	}
	return out, nil
}

// missing is how a run says it was started somewhere that holds no product.
func missing(detail string) error {
	return fmt.Errorf("%s\n%s", i18n.T("Nothing to run here."), detail)
}

// Path is where a module's folder is.
func (r *Runtime) Path(id string) string { return filepath.Join(r.Dir, DirModules, id) }

// root is where a run looks for everything it was shipped with: the folder
// named outright, or the one the binary is in.
func root(explicit string) (string, error) {
	dir := explicit
	if dir == "" {
		dir = binaryDir()
	}
	return filepath.Abs(dir)
}

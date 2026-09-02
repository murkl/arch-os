package spec

import (
	"fmt"
	"os"
	"path/filepath"
)

// FileRelease is the one yaml beside the binary that is not a tree.
//
// It has a reserved name because everything else ending in SpecExt up there
// declares a program, and a folder holding one is that program — see Trees. A
// release needs a way to say something about itself without turning the folder
// its programs sit in into a program of its own.
const FileRelease = "arch-os.yaml"

// Release is the product a binary and the trees beside it add up to: what it is
// called, and what it looks like.
//
// It is what no tree can answer for itself. An installer and a recovery of one
// release are two programs and one product — the same wordmark on the way in,
// the same colour on every page, the same name over the question of which of
// them to open — and a tree that declared any of that would be declaring it for
// its neighbours as well.
//
// A release that declares nothing is not an error. The runtime drives a tree
// found anywhere, and one on its own has no neighbours to agree with: it comes
// up in the interface's own colour and with no wordmark in front of it.
type Release struct {
	// Name is the product, over the page that asks which of its programs to
	// open. Not translated: it is a name, and the same one in every language.
	Name string `yaml:"name"`

	// Accent is the one colour everything on screen is built from, #rrggbb, and
	// Logo the wordmark the interface comes up out of — everything above the
	// first blank line a dim eyebrow over it.
	Accent string `yaml:"accent"`
	Logo   string `yaml:"logo"`

	// File is where this was read, empty where a release declared nothing.
	File string `yaml:"-"`
}

// LoadRelease reads the declaration beside the binary, or beside the folder
// named outright. Nothing there is a release with nothing to say rather than a
// failure, so the one caller never has to tell the two apart.
func LoadRelease(explicit string) (*Release, error) {
	dir, err := root(explicit)
	if err != nil {
		return nil, err
	}
	path := filepath.Join(dir, FileRelease)
	if _, err := os.Stat(path); err != nil {
		return &Release{}, nil
	}
	var r Release
	if err := read(path, &r); err != nil {
		return nil, err
	}
	if r.Accent != "" && !hexColor.MatchString(r.Accent) {
		return nil, fmt.Errorf("%s: accent must be #rrggbb, got %q", FileRelease, r.Accent)
	}
	r.File = path
	return &r, nil
}

// root is where a run looks for everything it was shipped with: the folder
// named outright, or the one the binary is in. Both of the two things found
// there — the release and the trees — resolve it the same way, because they are
// two halves of one folder.
func root(explicit string) (string, error) {
	dir := explicit
	if dir == "" {
		dir = binaryDir()
	}
	return filepath.Abs(dir)
}

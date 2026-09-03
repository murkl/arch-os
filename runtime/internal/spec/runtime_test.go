package spec

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// writeRuntime lays a runtime out the way a build does: the declaration beside
// however many modules, a folder each.
func writeRuntime(t *testing.T, declaration string, modules ...string) string {
	t.Helper()
	dir := t.TempDir()
	if declaration != "" {
		if err := os.WriteFile(filepath.Join(dir, FileRuntime), []byte(declaration), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	for _, name := range modules {
		sub := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Join(sub, DirTasks, "do"), 0o755); err != nil {
			t.Fatal(err)
		}
		write := func(path, body string) {
			if err := os.WriteFile(filepath.Join(sub, path), []byte(body), 0o600); err != nil {
				t.Fatal(err)
			}
		}
		write(name+Ext, "title: The "+name+"\nstages: [go]\n")
		write(filepath.Join(DirTasks, "do", FileTask), "name: Do it\nstage: go\n")
		write(filepath.Join(DirTasks, "do", FileScript), "echo hi\n")
	}
	return dir
}

const twoModules = "name: Test OS\nmodules: [installer, recovery]\n"

func TestLoadRuntimeReadsWhatEveryModuleShares(t *testing.T) {
	dir := writeRuntime(t, "name: Test OS\naccent: \"#1793d1\"\nlogo: |\n  Test\nmodules: [installer]\n", "installer")

	rt, err := LoadRuntime(dir)
	if err != nil {
		t.Fatal(err)
	}
	if rt.Name != "Test OS" {
		t.Errorf("name = %q, want Test OS", rt.Name)
	}
	if rt.Accent != "#1793d1" {
		t.Errorf("accent = %q", rt.Accent)
	}
	if rt.Logo != "Test\n" {
		t.Errorf("logo = %q", rt.Logo)
	}
	if rt.File != filepath.Join(dir, FileRuntime) {
		t.Errorf("file = %q", rt.File)
	}
}

// The list is the whole of what is on offer, in the order it is offered — so a
// module is added by writing a line and taken away by deleting one.
func TestTheModulesAreOfferedInTheOrderTheyAreListed(t *testing.T) {
	dir := writeRuntime(t, "name: Test OS\nmodules: [recovery, installer]\n", "installer", "recovery")

	rt, err := LoadRuntime(dir)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(rt.Modules, " ") != "recovery installer" {
		t.Errorf("modules = %v, want them in the order they were written", rt.Modules)
	}
	if !rt.Has("installer") || rt.Has("manager") {
		t.Error("Has() does not answer for what the list actually holds")
	}
	if got := rt.Path("installer"); got != filepath.Join(dir, "installer") {
		t.Errorf("Path() = %q, want the folder beside the declaration", got)
	}
}

// A folder that is there but not listed is not part of this product. Otherwise
// anything dropped beside the binary would become something the machine offers.
func TestAModuleFolderThatIsNotListedIsNotOffered(t *testing.T) {
	dir := writeRuntime(t, "name: Test OS\nmodules: [installer]\n", "installer", "recovery")

	rt, err := LoadRuntime(dir)
	if err != nil {
		t.Fatal(err)
	}
	if rt.Has("recovery") {
		t.Error("a folder nobody listed was offered")
	}
}

// A binary with nothing beside it is not a product yet, and saying so is better
// than coming up blank.
func TestARuntimeWithNoDeclarationWillNotStart(t *testing.T) {
	dir := writeRuntime(t, "", "installer")

	if _, err := LoadRuntime(dir); err == nil {
		t.Fatal("a folder with no runtime.yaml in it started anyway")
	}
}

func TestARuntimeThatOffersNothingWillNotStart(t *testing.T) {
	dir := writeRuntime(t, "name: Test OS\n")

	if _, err := LoadRuntime(dir); err == nil {
		t.Fatal("a runtime.yaml with no modules was accepted")
	} else if !strings.Contains(err.Error(), "no modules") {
		t.Errorf("error = %q, want it to say there are none", err)
	}
}

func TestARuntimeRefusesAModuleThatIsNotAFolderName(t *testing.T) {
	dir := writeRuntime(t, "name: Test OS\nmodules: [../elsewhere]\n")

	if _, err := LoadRuntime(dir); err == nil {
		t.Fatal("a path was accepted as a module name")
	}
}

func TestARuntimeRefusesTheSameModuleTwice(t *testing.T) {
	dir := writeRuntime(t, "name: Test OS\nmodules: [installer, installer]\n", "installer")

	if _, err := LoadRuntime(dir); err == nil {
		t.Fatal("the same module was accepted twice")
	}
}

func TestLoadRuntimeRefusesAnAccentThatIsNotAColour(t *testing.T) {
	dir := writeRuntime(t, "name: Test OS\naccent: blue\nmodules: [installer]\n", "installer")

	if _, err := LoadRuntime(dir); err == nil {
		t.Fatal("blue was accepted as a colour")
	} else if !strings.Contains(err.Error(), "accent must be") {
		t.Errorf("error = %q, want it to mention the accent", err)
	}
}

// The module's identity is its folder: what runtime.yaml lists, what the
// command line names, and what its answers are kept under are one word.
func TestAModuleIsIdentifiedByItsFolder(t *testing.T) {
	dir := writeRuntime(t, twoModules, "installer", "recovery")

	mod, err := Load(filepath.Join(dir, "recovery"))
	if err != nil {
		t.Fatal(err)
	}
	if mod.ID() != "recovery" {
		t.Errorf("ID() = %q, want recovery", mod.ID())
	}
}

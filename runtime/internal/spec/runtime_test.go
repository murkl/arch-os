package spec

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// writeRuntime lays a runtime out the way a build does: the declaration beside
// a modules folder, one folder in it per module.
func writeRuntime(t *testing.T, declaration string, modules ...string) string {
	t.Helper()
	dir := t.TempDir()
	if declaration != "" {
		if err := os.WriteFile(filepath.Join(dir, FileRuntime), []byte(declaration), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	for _, name := range modules {
		sub := filepath.Join(dir, DirModules, name)
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

const testRuntime = "name: Test OS\n"

func TestLoadRuntimeReadsWhatEveryModuleShares(t *testing.T) {
	dir := writeRuntime(t, "name: Test OS\naccent: \"#1793d1\"\nlogo: |\n  Test\n", "installer")

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

// The modules folder is the whole of what is on offer — so a module is added by
// dropping a folder in it and taken away by deleting one, with no list anywhere
// to keep in step.
func TestEveryFolderInTheModulesDirectoryIsOffered(t *testing.T) {
	dir := writeRuntime(t, testRuntime, "recovery", "installer")

	rt, err := LoadRuntime(dir)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(rt.Modules, " ") != "installer recovery" {
		t.Errorf("modules = %v, want every folder there, by name", rt.Modules)
	}
	if got := rt.Path("installer"); got != filepath.Join(dir, DirModules, "installer") {
		t.Errorf("Path() = %q, want the folder in %s", got, DirModules)
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
	dir := writeRuntime(t, testRuntime)

	if _, err := LoadRuntime(dir); err == nil {
		t.Fatal("a runtime with no modules beside it was accepted")
	} else if !strings.Contains(err.Error(), DirModules) {
		t.Errorf("error = %q, want it to name the folder it looked in", err)
	}
}

func TestLoadRuntimeRefusesAnAccentThatIsNotAColour(t *testing.T) {
	dir := writeRuntime(t, "name: Test OS\naccent: blue\n", "installer")

	if _, err := LoadRuntime(dir); err == nil {
		t.Fatal("blue was accepted as a colour")
	} else if !strings.Contains(err.Error(), "accent must be") {
		t.Errorf("error = %q, want it to mention the accent", err)
	}
}

// The module's identity is its folder: what the page offering it is keyed on,
// what the command line names, and what its answers are kept under are one word.
func TestAModuleIsIdentifiedByItsFolder(t *testing.T) {
	dir := writeRuntime(t, testRuntime, "installer", "recovery")

	mod, err := Load(filepath.Join(dir, DirModules, "recovery"))
	if err != nil {
		t.Fatal(err)
	}
	if mod.ID() != "recovery" {
		t.Errorf("ID() = %q, want recovery", mod.ID())
	}
}

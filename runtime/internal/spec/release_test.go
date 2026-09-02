package spec

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// writeRelease lays out a release the way a build does: the declaration beside
// however many trees, a folder each.
func writeRelease(t *testing.T, declaration string, trees ...string) string {
	t.Helper()
	dir := t.TempDir()
	if declaration != "" {
		if err := os.WriteFile(filepath.Join(dir, FileRelease), []byte(declaration), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	for _, name := range trees {
		sub := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Join(sub, DirTasks, "do"), 0o755); err != nil {
			t.Fatal(err)
		}
		write := func(path, body string) {
			if err := os.WriteFile(filepath.Join(sub, path), []byte(body), 0o600); err != nil {
				t.Fatal(err)
			}
		}
		write(name+SpecExt, "title: The "+name+"\nstages: [go]\n")
		write(filepath.Join(DirTasks, "do", FileTask), "name: Do it\nstage: go\n")
		write(filepath.Join(DirTasks, "do", FileScript), "echo hi\n")
	}
	return dir
}

func TestLoadReleaseReadsWhatTheProgramsShare(t *testing.T) {
	dir := writeRelease(t, "name: Test OS\naccent: \"#1793d1\"\nlogo: |\n  Test\n", "installer", "recovery")

	rel, err := LoadRelease(dir)
	if err != nil {
		t.Fatal(err)
	}
	if rel.Name != "Test OS" {
		t.Errorf("name = %q, want Test OS", rel.Name)
	}
	if rel.Accent != "#1793d1" {
		t.Errorf("accent = %q", rel.Accent)
	}
	if rel.Logo != "Test\n" {
		t.Errorf("logo = %q", rel.Logo)
	}
	if rel.File != filepath.Join(dir, FileRelease) {
		t.Errorf("file = %q", rel.File)
	}
}

// The declaration sits in the folder the programs sit in. Reading it as one of
// them would leave a release holding a single nameless program and hide the two
// that are actually there.
func TestTheReleaseDeclarationIsNotATree(t *testing.T) {
	dir := writeRelease(t, "name: Test OS\n", "installer", "recovery")

	trees, err := Trees(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(trees) != 2 {
		t.Fatalf("trees = %v, want the two folders", trees)
	}
	for i, want := range []string{"installer", "recovery"} {
		if filepath.Base(trees[i]) != want {
			t.Errorf("tree %d = %q, want %q", i, filepath.Base(trees[i]), want)
		}
	}
}

// A tree found on its own, with no release around it, is the whole point of a
// runtime that knows nothing about what it drives.
func TestAReleaseThatDeclaresNothingIsNotAFailure(t *testing.T) {
	dir := writeRelease(t, "", "installer")

	rel, err := LoadRelease(dir)
	if err != nil {
		t.Fatal(err)
	}
	if rel.File != "" || rel.Name != "" || rel.Accent != "" || rel.Logo != "" {
		t.Errorf("release = %+v, want nothing declared", rel)
	}
}

func TestLoadReleaseRefusesAnAccentThatIsNotAColour(t *testing.T) {
	dir := writeRelease(t, "name: Test OS\naccent: blue\n", "installer")

	if _, err := LoadRelease(dir); err == nil {
		t.Fatal("blue was accepted as a colour")
	} else if !strings.Contains(err.Error(), "accent must be") {
		t.Errorf("error = %q, want it to mention the accent", err)
	}
}

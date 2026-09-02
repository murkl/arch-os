package main

import (
	"maps"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"installer/internal/i18n"
	"installer/internal/spec"
)

// tree writes the smallest installer tree that will load, plus whatever extra
// files a test needs, and answers with the folder it put them in.
func tree(t *testing.T, declaration string, extra map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	files := map[string]string{
		"installer.yaml":        declaration,
		"tasks/first/task.yaml": "name: First\nstage: go\n",
		"tasks/first/task.sh":   "true\n",
	}
	maps.Copy(files, extra)
	for name, body := range files {
		path := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func load(t *testing.T, dir string) *spec.Spec {
	t.Helper()
	sp, err := spec.Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	return sp
}

func TestTheMachineLocaleIsReadInPosixOrder(t *testing.T) {
	for _, tc := range []struct {
		name string
		env  map[string]string
		want string
	}{
		{"LC_ALL beats the rest", map[string]string{"LC_ALL": "de_DE.UTF-8", "LC_MESSAGES": "fr_FR", "LANG": "it_IT"}, "de_DE.UTF-8"},
		{"LC_MESSAGES beats LANG", map[string]string{"LC_MESSAGES": "fr_FR", "LANG": "it_IT"}, "fr_FR"},
		{"LANG is the last word", map[string]string{"LANG": "it_IT"}, "it_IT"},
		{"an empty value is no answer", map[string]string{"LC_ALL": "", "LANG": "it_IT"}, "it_IT"},
		{"nothing set is no answer", nil, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			for _, key := range []string{"LC_ALL", "LC_MESSAGES", "LANG"} {
				t.Setenv(key, "")
				os.Unsetenv(key)
			}
			for key, value := range tc.env {
				t.Setenv(key, value)
			}
			if got := locale(); got != tc.want {
				t.Errorf("locale() = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestASavedLanguageBeatsTheMachineLocale(t *testing.T) {
	t.Setenv("LC_ALL", "fr_FR.UTF-8")
	langs := []i18n.Lang{{Code: "en"}, {Code: "de"}, {Code: "fr"}}
	if got := language("de", langs); got != "de" {
		t.Errorf("language() = %q, want de — a stored choice is somebody having said so", got)
	}
}

func TestAMachineLocaleSettlesTheLanguageWhenNothingWasSaved(t *testing.T) {
	t.Setenv("LC_ALL", "de_AT.UTF-8")
	langs := []i18n.Lang{{Code: "en"}, {Code: "de"}}
	if got := language("", langs); got != "de" {
		t.Errorf("language() = %q, want de — de_AT is German", got)
	}
}

func TestALanguageNoLongerOnOfferFallsBackToTheMachineLocale(t *testing.T) {
	t.Setenv("LC_ALL", "de_DE.UTF-8")
	langs := []i18n.Lang{{Code: "en"}, {Code: "de"}}
	if got := language("fr", langs); got != "de" {
		t.Errorf("language() = %q, want de — a saved code no catalog answers to is not an answer", got)
	}
}

func TestAnUntranslatableMachineLeavesTheSourceLanguage(t *testing.T) {
	t.Setenv("LC_ALL", "C")
	langs := []i18n.Lang{{Code: "en"}, {Code: "de"}}
	if got := language("", langs); got != i18n.SourceLang {
		t.Errorf("language() = %q, want %q", got, i18n.SourceLang)
	}
}

// A release is the binary and the trees beside it. All of them are read at
// startup, so one that will not load is a message before anything is offered
// rather than a row that fails when it is chosen.
func TestEveryTreeOfAReleaseIsRead(t *testing.T) {
	release := t.TempDir()
	for _, name := range []string{"installer", "recovery"} {
		if err := os.Rename(tree(t, "title: "+name+"\nstages: [go]\n", nil), filepath.Join(release, name)); err != nil {
			t.Fatal(err)
		}
	}
	got, err := loadTrees(release)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].UI.Title != "installer" || got[1].UI.Title != "recovery" {
		t.Errorf("loadTrees() = %d trees, want the two beside the binary in folder order", len(got))
	}
}

func TestAReleaseHoldingABrokenTreeWillNotStart(t *testing.T) {
	release := t.TempDir()
	if err := os.Rename(tree(t, "title: T\nstages: [go]\n", nil), filepath.Join(release, "installer")); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(tree(t, "title: T\n", nil), filepath.Join(release, "recovery")); err != nil {
		t.Fatal(err)
	}
	if _, err := loadTrees(release); err == nil {
		t.Fatal("a release with a tree that declares no stages was read as sound")
	}
}

func TestOnlyTheHooksATreeActuallyHasAreListed(t *testing.T) {
	sp := load(t, tree(t, "title: T\nstages: [go]\n", map[string]string{
		"hooks/preflight.sh": "true\n",
		"hooks/restart.sh":   "true\n",
	}))
	got := strings.Join(hooks(sp), " ")
	if got != "preflight restart" {
		t.Errorf("hooks() = %q, want \"preflight restart\" in HookNames order", got)
	}
}

func TestATreeWithNoCatalogsSpeaksTheRuntimesOwn(t *testing.T) {
	sp := load(t, tree(t, "title: T\nstages: [go]\n", nil))
	if got := len(catalogs(sp)); got != 1 {
		t.Errorf("catalogs() has %d sources, want 1 — the runtime's alone", got)
	}
}

func TestATreesCatalogsAreLaidOverTheRuntimes(t *testing.T) {
	sp := load(t, tree(t, "title: T\nstages: [go]\n", map[string]string{
		"locales/de.po": "msgid \"Back\"\nmsgstr \"Zurück\"\n",
	}))
	sources := catalogs(sp)
	if len(sources) != 2 {
		t.Fatalf("catalogs() has %d sources, want 2", len(sources))
	}
	codes := codes(i18n.Discover(sources...))
	if strings.Join(codes, " ") != "en de" {
		t.Errorf("languages = %v, want [en de]", codes)
	}
}

func TestTheTemplateOfATreeHoldsEveryWordItSays(t *testing.T) {
	dir := tree(t, `
title: Installer
stages: [go]
variables:
  - name: HOST
    title: Host name
    description: |
      The name this machine has.

      It is the one the network knows it by.
`, nil)
	out := captureStdout(t, func() {
		if err := catalog(dir); err != nil {
			t.Fatal(err)
		}
	})
	if _, err := i18n.Parse([]byte(out)); err != nil {
		t.Fatalf("the template is not readable po: %v\n%s", err, out)
	}
	for _, want := range []string{
		`msgid "Installer"`,
		`msgid "Host name"`,
		// Paragraphs are written as lines, so a translator reads them as they
		// will be read.
		"msgid \"\"\n\"The name this machine has.\\n\"\n\"\\n\"\n\"It is the one the network knows it by.\"",
		// And every one of them says where it was read.
		"#: installer.yaml",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("the template has no %q in it:\n%s", want, out)
		}
	}
}

func TestInspectingATreeNamesEverythingItHolds(t *testing.T) {
	dir := tree(t, `
title: Installer
stages: [go]
variables:
  - name: HOST
    title: Host name
    required: true
  - name: PASSWORD
    title: Password
    type: secret
    required: true
`, map[string]string{
		"hooks/preflight.sh": "true\n",
		// The one task reads both answers, so the report is about what the tree
		// holds rather than about a guard that disagrees — see spec.Unread.
		"tasks/first/task.sh": "echo \"$HOST $PASSWORD\"\n",
	})
	out := captureStdout(t, func() {
		if err := inspect(dir); err != nil {
			t.Fatal(err)
		}
	})
	for _, want := range []string{
		"title      Installer",
		"variables  2 (2 required, 1 secret)",
		"tasks      1",
		"hooks      preflight",
		"1. go         first",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("the report does not say %q:\n%s", want, out)
		}
	}
}

// A tree that behaves is not a tree that refuses to start, so this is the one
// thing -check has to say that loading it never will.
func TestInspectingRefusesAQuestionNothingReadsTheAnswerOf(t *testing.T) {
	dir := tree(t, `
title: Installer
stages: [go]
variables:
  - name: SPARE
    title: Spare
`, nil)
	if _, err := spec.Load(dir); err != nil {
		t.Fatalf("the tree does not load, and it has to: %v", err)
	}
	var err error
	captureStdout(t, func() { err = inspect(dir) })
	if err == nil {
		t.Fatal("a question nothing reads was reported as fine")
	}
	if !strings.Contains(err.Error(), "nothing reads the answer") {
		t.Errorf("inspect() = %v, want it to say nothing reads the answer", err)
	}
}

func TestInspectingSaysWhatIsWrongWithATreeThatWillNotLoad(t *testing.T) {
	dir := tree(t, "stages: [go]\n", nil) // no title
	if err := inspect(dir); err == nil {
		t.Fatal("a tree with no title loaded; it must not")
	}
}

// captureStdout runs f with stdout redirected and answers with what it printed.
// The two commands under test report by printing, which is the whole of what
// they do.
func captureStdout(t *testing.T, f func()) string {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	saved := os.Stdout
	os.Stdout = w
	done := make(chan string)
	go func() {
		var b strings.Builder
		buf := make([]byte, 4096)
		for {
			n, err := r.Read(buf)
			b.Write(buf[:n])
			if err != nil {
				break
			}
		}
		done <- b.String()
	}()
	f()
	w.Close()
	os.Stdout = saved
	return <-done
}

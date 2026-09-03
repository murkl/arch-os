package main

import (
	"maps"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/murkl/arch-os/runtime/internal/i18n"
	"github.com/murkl/arch-os/runtime/internal/spec"
)

// writeModule writes the smallest module that will load, plus whatever extra
// files a test needs, and answers with the folder it put them in.
func writeModule(t *testing.T, declaration string, extra map[string]string) string {
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

// runtime lays a whole product out: a runtime.yaml over however many modules,
// each of them the smallest one that will load.
func runtime(t *testing.T, declaration string, modules ...string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, spec.FileRuntime), []byte(declaration), 0o600); err != nil {
		t.Fatal(err)
	}
	for _, name := range modules {
		if err := os.Rename(writeModule(t, "title: "+name+"\nstages: [go]\n", nil), filepath.Join(dir, name)); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

// around puts a runtime.yaml over one module folder, so a module written on
// its own can be read the way the program reads one.
func around(t *testing.T, mod string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, spec.FileRuntime), []byte("name: Test OS\nmodules: [installer]\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(mod, filepath.Join(dir, "installer")); err != nil {
		t.Fatal(err)
	}
	return dir
}

func loaded(t *testing.T, dir string) *spec.Module {
	t.Helper()
	mod, err := spec.Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	return mod
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

// Every module is read at startup, so one that will not load is a message
// before anything is offered rather than a row that fails when it is chosen.
func TestEveryModuleOfARuntimeIsRead(t *testing.T) {
	dir := runtime(t, "name: Test OS\nmodules: [installer, recovery]\n", "installer", "recovery")

	rt, err := spec.LoadRuntime(dir)
	if err != nil {
		t.Fatal(err)
	}
	got, err := load(rt, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].UI.Title != "installer" || got[1].UI.Title != "recovery" {
		t.Errorf("load() = %d modules, want the two it lists, in that order", len(got))
	}
}

// Naming one is the question of which to open, already answered — so only that
// one is read, and nothing else it ships with can stop it starting.
func TestNamingAModuleReadsOnlyThatOne(t *testing.T) {
	dir := runtime(t, "name: Test OS\nmodules: [installer, recovery]\n", "installer", "recovery")

	rt, err := spec.LoadRuntime(dir)
	if err != nil {
		t.Fatal(err)
	}
	got, err := load(rt, "recovery")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].UI.Title != "recovery" {
		t.Errorf("load() = %d modules, want only the one that was named", len(got))
	}
}

// Whether a name is a module is settled by runtime.yaml at the moment it is
// given, which is what keeps the list of them out of this program.
func TestAModuleNobodyDeclaredIsRefusedByName(t *testing.T) {
	dir := runtime(t, "name: Test OS\nmodules: [installer]\n", "installer")

	rt, err := spec.LoadRuntime(dir)
	if err != nil {
		t.Fatal(err)
	}
	_, err = load(rt, "manager")
	if err == nil {
		t.Fatal("a module nobody declared was opened")
	}
	if !strings.Contains(err.Error(), "installer") {
		t.Errorf("error = %q, want it to say what is on offer", err)
	}
}

func TestARuntimeHoldingABrokenModuleWillNotStart(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, spec.FileRuntime), []byte("name: T\nmodules: [installer, recovery]\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(writeModule(t, "title: T\nstages: [go]\n", nil), filepath.Join(dir, "installer")); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(writeModule(t, "title: T\n", nil), filepath.Join(dir, "recovery")); err != nil {
		t.Fatal(err)
	}
	rt, err := spec.LoadRuntime(dir)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := load(rt, ""); err == nil {
		t.Fatal("a runtime with a module that declares no stages was read as sound")
	}
}

// The one word on the command line that is not a flag is the module, with or
// without the dashes an option would carry, and wherever it stands.
func TestTheModuleIsTheWordAtTheFrontOfTheCommandLine(t *testing.T) {
	for _, tc := range []struct {
		name string
		args []string
		want string
		conf string
	}{
		{"as an option", []string{"--installer"}, "installer", ""},
		{"as a word", []string{"installer"}, "installer", ""},
		{"with one dash", []string{"-recovery"}, "recovery", ""},
		{"in front of the flags", []string{"--recovery", "-conf", "x"}, "recovery", "x"},
		{"behind them", []string{"-conf", "x", "installer"}, "installer", "x"},
		{"between them", []string{"-conf", "x", "--installer", "-version"}, "installer", "x"},
		{"nothing at all", nil, "", ""},
		{"a flag is not a module", []string{"-conf", "x"}, "", "x"},
		{"nor is its value", []string{"-conf", "installer"}, "", "installer"},
		{"nor is one with its value attached", []string{"-conf=x"}, "", "x"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("RUNTIME_CONF", "")
			got := parse(tc.args)
			if got.module != tc.want {
				t.Errorf("parse(%v).module = %q, want %q", tc.args, got.module, tc.want)
			}
			if got.conf != tc.conf {
				t.Errorf("parse(%v).conf = %q, want %q", tc.args, got.conf, tc.conf)
			}
		})
	}
}

func TestOnlyTheHooksAModuleActuallyHasAreListed(t *testing.T) {
	mod := loaded(t, writeModule(t, "title: T\nstages: [go]\n", map[string]string{
		"hooks/preflight.sh": "true\n",
		"hooks/restart.sh":   "true\n",
	}))
	got := strings.Join(hooks(mod), " ")
	if got != "preflight restart" {
		t.Errorf("hooks() = %q, want \"preflight restart\" in HookNames order", got)
	}
}

func TestAModuleWithNoCatalogsSpeaksTheRuntimesOwn(t *testing.T) {
	mod := loaded(t, writeModule(t, "title: T\nstages: [go]\n", nil))
	if got := len(catalogs(mod)); got != 1 {
		t.Errorf("catalogs() has %d sources, want 1 — the runtime's alone", got)
	}
}

func TestAModulesCatalogsAreLaidOverTheRuntimes(t *testing.T) {
	mod := loaded(t, writeModule(t, "title: T\nstages: [go]\n", map[string]string{
		"locales/de.po": "msgid \"Back\"\nmsgstr \"Zurück\"\n",
	}))
	sources := catalogs(mod)
	if len(sources) != 2 {
		t.Fatalf("catalogs() has %d sources, want 2", len(sources))
	}
	codes := codes(i18n.Discover(sources...))
	if strings.Join(codes, " ") != "en de" {
		t.Errorf("languages = %v, want [en de]", codes)
	}
}

func TestTheTemplateOfAModuleHoldsEveryWordItSays(t *testing.T) {
	dir := around(t, writeModule(t, `
title: Installer
stages: [go]
variables:
  - name: HOST
    title: Host name
    description: |
      The name this machine has.

      It is the one the network knows it by.
`, nil))
	out := captureStdout(t, func() {
		if err := catalog(dir, "installer"); err != nil {
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

func TestInspectingAModuleNamesEverythingItHolds(t *testing.T) {
	dir := around(t, writeModule(t, `
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
		// The one task reads both answers, so the report is about what the
		// module holds rather than about a guard that disagrees — see
		// spec.Unread.
		"tasks/first/task.sh": "echo \"$HOST $PASSWORD\"\n",
	}))
	out := captureStdout(t, func() {
		if err := inspect(dir, ""); err != nil {
			t.Fatal(err)
		}
	})
	for _, want := range []string{
		"modules    installer",
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

// A module that behaves is not a module that refuses to start, so this is the
// one thing -check has to say that loading it never will.
func TestInspectingRefusesAQuestionNothingReadsTheAnswerOf(t *testing.T) {
	mod := writeModule(t, `
title: Installer
stages: [go]
variables:
  - name: SPARE
    title: Spare
`, nil)
	if _, err := spec.Load(mod); err != nil {
		t.Fatalf("the module does not load, and it has to: %v", err)
	}
	dir := around(t, mod)
	var err error
	captureStdout(t, func() { err = inspect(dir, "") })
	if err == nil {
		t.Fatal("a question nothing reads was reported as fine")
	}
	if !strings.Contains(err.Error(), "nothing reads the answer") {
		t.Errorf("inspect() = %v, want it to say nothing reads the answer", err)
	}
}

func TestInspectingSaysWhatIsWrongWithAModuleThatWillNotLoad(t *testing.T) {
	dir := around(t, writeModule(t, "stages: [go]\n", nil)) // no title
	if err := inspect(dir, ""); err == nil {
		t.Fatal("a module with no title loaded; it must not")
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

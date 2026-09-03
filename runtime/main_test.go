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

// runtimeDecl is a product with nothing to say about itself but its name: what
// it offers is the folders beside it, so a test that is not about the runtime
// writes no more than this.
const runtimeDecl = "name: Test OS\n"

// runtime lays a whole product out: a runtime.yaml over a modules folder, each
// module in it the smallest one that will load.
func runtime(t *testing.T, declaration string, modules ...string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, spec.FileRuntime), []byte(declaration), 0o600); err != nil {
		t.Fatal(err)
	}
	for _, name := range modules {
		put(t, dir, name, writeModule(t, "title: "+name+"\nstages: [go]\n", nil))
	}
	return dir
}

// around puts a runtime.yaml over one module folder, so a module written on
// its own can be read the way the program reads one.
func around(t *testing.T, mod string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, spec.FileRuntime), []byte(runtimeDecl), 0o600); err != nil {
		t.Fatal(err)
	}
	put(t, dir, "installer", mod)
	return dir
}

// put moves a module folder into the place a runtime looks for it.
func put(t *testing.T, dir, name, mod string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(dir, spec.DirModules), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(mod, filepath.Join(dir, spec.DirModules, name)); err != nil {
		t.Fatal(err)
	}
}

// product loads a whole product the way a run does: the runtime.yaml in a
// folder, and every module beside it.
func product(t *testing.T, dir string) (*spec.Runtime, []*spec.Module) {
	t.Helper()
	rt, err := spec.LoadRuntime(dir)
	if err != nil {
		t.Fatal(err)
	}
	mods, err := load(rt)
	if err != nil {
		t.Fatal(err)
	}
	return rt, mods
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
	dir := runtime(t, runtimeDecl, "installer", "recovery")

	rt, err := spec.LoadRuntime(dir)
	if err != nil {
		t.Fatal(err)
	}
	got, err := load(rt)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].UI.Title != "installer" || got[1].UI.Title != "recovery" {
		t.Errorf("load() = %d modules, want both of them, in name order", len(got))
	}
}

// Naming one is the question of which to open, already answered — so the run
// narrows to it, whatever else was read alongside it.
func TestNamingAModuleNarrowsTheRunToIt(t *testing.T) {
	rt, mods := product(t, runtime(t, runtimeDecl, "installer", "recovery"))

	got, err := pick(rt, mods, "recovery")
	if err != nil {
		t.Fatal(err)
	}
	if got == nil || got.UI.Title != "recovery" {
		t.Fatalf("pick() = %v, want the one that was named", got)
	}
	if only(mods, got)[0] != got || len(only(mods, got)) != 1 {
		t.Error("the run was not narrowed to the module that was named")
	}
	if len(only(mods, nil)) != 2 {
		t.Error("a run that named none was narrowed anyway")
	}
}

// Whether a name is a module is settled by what is beside the binary at the
// moment it is given, which is what keeps the list of them out of this program.
func TestAModuleNobodyDeclaredIsRefusedByName(t *testing.T) {
	rt, mods := product(t, runtime(t, runtimeDecl, "installer"))

	_, err := pick(rt, mods, "manager")
	if err == nil {
		t.Fatal("a module nobody declared was opened")
	}
	if !strings.Contains(err.Error(), "installer") {
		t.Errorf("error = %q, want it to say what is on offer", err)
	}
}

func TestARuntimeHoldingABrokenModuleWillNotStart(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, spec.FileRuntime), []byte(runtimeDecl), 0o600); err != nil {
		t.Fatal(err)
	}
	put(t, dir, "installer", writeModule(t, "title: T\nstages: [go]\n", nil))
	put(t, dir, "recovery", writeModule(t, "title: T\n", nil))
	rt, err := spec.LoadRuntime(dir)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := load(rt); err == nil {
		t.Fatal("a runtime with a module that declares no stages was read as sound")
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

func TestAModuleThatWillNotLoadSaysWhatIsWrongWithIt(t *testing.T) {
	dir := around(t, writeModule(t, "stages: [go]\n", nil)) // no title
	rt, err := spec.LoadRuntime(dir)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := load(rt); err == nil {
		t.Fatal("a module with no title loaded; it must not")
	}
}

// The whole of what a command line says: which module to open, and the two
// words that are not one. A module is written as a word or with the dashes an
// option would carry, and may stand anywhere among them.
func TestACommandLineIsAModuleAndTheRuntimesOwnTwoWords(t *testing.T) {
	for _, tc := range []struct {
		name    string
		args    []string
		module  string
		debug   bool
		version bool
	}{
		{name: "nothing at all"},
		{name: "a bare word", args: []string{"installer"}, module: "installer"},
		{name: "the same word with dashes", args: []string{"--installer"}, module: "installer"},
		{name: "one dash is the same request", args: []string{"-installer"}, module: "installer"},
		{name: "in front of the module", args: []string{"--debug", "installer"}, module: "installer", debug: true},
		{name: "behind it", args: []string{"installer", "--debug"}, module: "installer", debug: true},
		{name: "the version on its own", args: []string{"--version"}, version: true},
		{name: "both of the runtime's own", args: []string{"--debug", "--version"}, debug: true, version: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parse(tc.args)
			if err != nil {
				t.Fatal(err)
			}
			if got.module != tc.module || got.debug != tc.debug || got.version != tc.version {
				t.Errorf("parse(%v) = %+v, want module %q, debug %v, version %v",
					tc.args, got, tc.module, tc.debug, tc.version)
			}
		})
	}
}

func TestACommandLineThatCannotBeReadIsRefused(t *testing.T) {
	for _, tc := range []struct {
		name string
		args []string
		want string
	}{
		{"two modules", []string{"installer", "recovery"}, "One module at a time"},
		{"a dash on its own", []string{"-"}, "names nothing"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := parse(tc.args)
			if err == nil {
				t.Fatal("the line was read as sound")
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Errorf("error = %q, want it to mention %q", err, tc.want)
			}
		})
	}
}

// The two words are the runtime's wherever they turn up, so a folder named
// after one of them is a module nobody could ever open — said at startup rather
// than found out by typing it.
func TestAModuleNamedAfterTheRuntimesOwnWordsWillNotStart(t *testing.T) {
	dir := runtime(t, runtimeDecl, "installer", "debug")
	rt, err := spec.LoadRuntime(dir)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := load(rt); err == nil {
		t.Fatal("a module called debug loaded; nothing could ever open it")
	}
}

// The one wire between the command line and a script: --debug reaches every one
// of them as DEBUG, and a run without it says so rather than saying nothing.
func TestDebugOnTheCommandLineReachesEveryScript(t *testing.T) {
	for _, debug := range []bool{false, true} {
		mod := loaded(t, writeModule(t, "title: T\nstages: [go]\n", nil))
		t.Chdir(t.TempDir())

		p, err := open(mod, debug)
		if err != nil {
			t.Fatal(err)
		}
		want := spec.DebugVar + "=" + spec.BoolFalse
		if debug {
			want = spec.DebugVar + "=" + spec.BoolTrue
		}
		if env := strings.Join(p.Store.Env(), "\n"); !strings.Contains(env, want) {
			t.Errorf("open(debug=%v) hands a script no %q", debug, want)
		}
	}
}

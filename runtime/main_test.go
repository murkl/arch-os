package main

import (
	"maps"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/murkl/arch-os/runtime/internal/cli"
	"github.com/murkl/arch-os/runtime/internal/i18n"
	"github.com/murkl/arch-os/runtime/internal/runner"
	"github.com/murkl/arch-os/runtime/internal/spec"
	"github.com/murkl/arch-os/runtime/internal/store"
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
	rt, mods := product(t, dir)
	out := captureStdout(t, func() {
		if err := catalog(rt, mods); err != nil {
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
    flag: password
    type: secret
    required: true
`, map[string]string{
		"hooks/preflight.sh": "true\n",
		// The one task reads both answers, so the report is about what the
		// module holds rather than about a guard that disagrees — see
		// spec.Unread.
		"tasks/first/task.sh": "echo \"$HOST $PASSWORD\"\n",
	}))
	rt, mods := product(t, dir)
	out := captureStdout(t, func() {
		if err := inspect(rt, mods); err != nil {
			t.Fatal(err)
		}
	})
	for _, want := range []string{
		"modules    installer",
		"title      Installer",
		"variables  2 (2 required, 1 secret)",
		"tasks      1",
		"hooks      preflight",
		"flags      --password",
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
	rt, mods := product(t, around(t, mod))
	var err error
	captureStdout(t, func() { err = inspect(rt, mods) })
	if err == nil {
		t.Fatal("a question nothing reads was reported as fine")
	}
	if !strings.Contains(err.Error(), "nothing reads the answer") {
		t.Errorf("inspect() = %v, want it to say nothing reads the answer", err)
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

// What a command line says reaches the answers the same way anything else does,
// and is held to the same rules — so a wrong value stops a run rather than
// reaching a script.
func TestTheCommandLineAnswersQuestionsAndHandsOverOptions(t *testing.T) {
	mod := loaded(t, writeModule(t, `
title: T
stages: [go]
variables:
  - name: DISK
    title: Disk
    flag: disk
    values: [/dev/sda, /dev/sdb]
    required: true
  - name: PASSWORD
    title: Password
    flag: password
    type: secret
    required: true
options:
  - name: DEBUG
    flag: debug
    title: Simulate it.
    type: bool
    default: false
`, nil))
	st := store.New(mod, filepath.Join(t.TempDir(), "t.conf"))

	given, err := apply(mod, st, read(t, mod, "--disk=/dev/sdb", "--password=hunter2", "--debug"))
	if err != nil {
		t.Fatal(err)
	}
	if got := st.Get("DISK"); got != "/dev/sdb" {
		t.Errorf("DISK = %q, want /dev/sdb", got)
	}
	if got := st.Get("PASSWORD"); got != "hunter2" {
		t.Errorf("PASSWORD = %q, want what the line gave", got)
	}
	if got := st.Get("DEBUG"); got != "true" {
		t.Errorf("DEBUG = %q, want true", got)
	}
	if !given["DISK"] || !given["PASSWORD"] {
		t.Errorf("given = %v, want both questions marked as answered by the line", given)
	}
	if given["DEBUG"] {
		t.Error("an option was reported as a question the line answered")
	}
}

// An option every script is handed whether the line mentioned it or not: a
// script testing it must never be testing an empty string.
func TestAnOptionIsHandedOverEvenWhenTheLineIsSilent(t *testing.T) {
	mod := loaded(t, writeModule(t, `
title: T
stages: [go]
options:
  - name: DEBUG
    flag: debug
    title: Simulate it.
    type: bool
    default: false
`, nil))
	st := store.New(mod, filepath.Join(t.TempDir(), "t.conf"))
	if _, err := apply(mod, st, read(t, mod)); err != nil {
		t.Fatal(err)
	}
	if got := st.Get("DEBUG"); got != "false" {
		t.Errorf("DEBUG = %q, want the declared default", got)
	}
}

func TestAValueTheDeclarationRefusesStopsTheRun(t *testing.T) {
	mod := loaded(t, writeModule(t, `
title: T
stages: [go]
variables:
  - name: DISK
    title: Disk
    flag: disk
    values: [/dev/sda]
    error: Choose a disk that exists.
`, nil))
	st := store.New(mod, filepath.Join(t.TempDir(), "t.conf"))
	_, err := apply(mod, st, read(t, mod, "--disk=/dev/nope"))
	if err == nil {
		t.Fatal("a value no answer may have was taken from the command line")
	}
	if !strings.Contains(err.Error(), "--disk") || !strings.Contains(err.Error(), "Choose a disk") {
		t.Errorf("error = %q, want it to name the flag and say why", err)
	}
}

// A run nobody is watching says which questions are open and stops, rather than
// handing a script an empty string.
func TestAForcedRunWithAQuestionOpenWillNotStart(t *testing.T) {
	mod := loaded(t, writeModule(t, `
title: T
stages: [go]
variables:
  - name: DISK
    title: Disk
    required: true
  - name: PASSWORD
    title: Password
    flag: password
    type: secret
    required: true
`, nil))
	st := store.New(mod, filepath.Join(t.TempDir(), "t.conf"))
	err := ready(st)
	if err == nil {
		t.Fatal("a run with two questions open was reported as ready")
	}
	for _, want := range []string{"DISK", "PASSWORD", "--password"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error = %q, want it to name %q", err, want)
		}
	}

	st.Set("DISK", "/dev/sda")
	st.Set("PASSWORD", "hunter2")
	if err := ready(st); err != nil {
		t.Errorf("ready() = %v, want nothing once everything is answered", err)
	}
}

// read is a command line as a run reads one: against the runtime's own flags
// and the module's, together.
func read(t *testing.T, mod *spec.Module, args ...string) *cli.Command {
	t.Helper()
	flags, err := line([]*spec.Module{mod})
	if err != nil {
		t.Fatal(err)
	}
	cmd, err := cli.Parse(args, flags)
	if err != nil {
		t.Fatal(err)
	}
	return cmd
}

// A starting point that is fetched rather than written out is chosen in the
// interface by picking its row and typing the code. Giving the code on the
// command line is the same choice, so the same shell runs and what it wrote
// becomes the answers of this run.
func TestGivingTheCodeOfAFetchedStartingPointFetchesIt(t *testing.T) {
	mod := loaded(t, writeModule(t, `
title: T
stages: [go]
presets:
  - id: start
    title: Start
    options:
      - id: shared
        title: Shared
        asks: SOURCE
        apply: ./import.sh
variables:
  - name: SOURCE
    title: Configuration code
    flag: config
    required: true
  - name: HOST
    title: Host
    required: true
`, map[string]string{
		// The answer file is the one way a script answers anything.
		"import.sh": "printf \"HOST='%s'\\n\" \"$SOURCE\" >>\"$MODULE_CONF\"\n",
	}))
	st := store.New(mod, filepath.Join(t.TempDir(), "t.conf"))
	st.SetFacts("test")
	rn := runner.New(mod, st)

	given, err := apply(mod, st, read(t, mod, "--config=elsewhere"))
	if err != nil {
		t.Fatal(err)
	}
	if err := fetch(mod, st, rn, given); err != nil {
		t.Fatal(err)
	}
	if got := st.Get("HOST"); got != "elsewhere" {
		t.Errorf("HOST = %q, want what the fetched configuration answered", got)
	}
	if err := ready(st); err != nil {
		t.Errorf("ready() = %v, want nothing — the fetch answered the last question", err)
	}
}

// Only a code this run was given. One already in the answer file was fetched by
// the run that put it there, and fetching it again would put a pastebin between
// a machine and its own answers.
func TestACodeAlreadyInTheAnswerFileIsNotFetchedAgain(t *testing.T) {
	mod := loaded(t, writeModule(t, `
title: T
stages: [go]
presets:
  - id: start
    title: Start
    options:
      - id: shared
        title: Shared
        asks: SOURCE
        apply: ./import.sh
variables:
  - name: SOURCE
    title: Configuration code
    flag: config
  - name: HOST
    title: Host
`, map[string]string{
		"import.sh": "printf \"HOST='fetched'\\n\" >>\"$MODULE_CONF\"\n",
	}))
	st := store.New(mod, filepath.Join(t.TempDir(), "t.conf"))
	st.SetFacts("test")
	st.Set("SOURCE", "elsewhere")
	if err := fetch(mod, st, runner.New(mod, st), map[string]bool{}); err != nil {
		t.Fatal(err)
	}
	if got := st.Get("HOST"); got != "" {
		t.Errorf("HOST = %q, want nothing — nothing was fetched", got)
	}
}

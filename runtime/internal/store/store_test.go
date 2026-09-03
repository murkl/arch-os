package store

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/murkl/arch-os/runtime/internal/spec"
)

// What a test module's declaration is called: the runtime takes whichever yaml
// it finds in the folder, and these tests use the name the real ones use.
const treeFile = "installer.yaml"

// setup builds a store over a module written for the test, with the answer file
// inside a temporary directory of its own.
func setup(t *testing.T, variables string) *Store {
	t.Helper()
	return New(load(t, "title: T\nstages: [go]\n"+variables), filepath.Join(t.TempDir(), "installer.conf"))
}

// load writes the smallest module that will load — the given installer.yaml and
// one task — and reads it back.
func load(t *testing.T, installer string) *spec.Module {
	t.Helper()
	dir := t.TempDir()
	files := map[string]string{
		treeFile:             installer,
		"tasks/go/task.yaml": "name: Go\nstage: go\n",
		"tasks/go/task.sh":   "true\n",
	}
	for name, body := range files {
		path := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	sp, err := spec.Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	return sp
}

const twoVars = `
variables:
  - name: USER
    title: User
    required: true
    pattern: '^[a-z]+$'
    error: Lower case letters only.
  - name: HOST
    title: Host
    default: arch-os
`

func TestMissingIsWhatIsStillOpen(t *testing.T) {
	s := setup(t, twoVars)
	if names := names(s.Missing()); strings.Join(names, ",") != "USER" {
		t.Errorf("missing = %v, want just USER — HOST has a default", names)
	}
	s.Set("USER", "moritz")
	if got := s.Missing(); len(got) != 0 {
		t.Errorf("missing = %v, want nothing left", names(got))
	}
}

// A value edited straight into the answer file never passed a prompt, so it is
// held to the same rules — and an invalid one puts the question back rather
// than reaching a script.
func TestAnInvalidStoredValueIsStillMissing(t *testing.T) {
	s := setup(t, twoVars)
	s.Set("USER", "Moritz1")
	got := s.Missing()
	if len(got) != 1 || got[0].Name != "USER" {
		t.Fatalf("missing = %v, want USER back", names(got))
	}
	if why := s.Invalid(got[0], "Moritz1"); why != "Lower case letters only." {
		t.Errorf("reason = %q", why)
	}
}

func TestSecretsAreNeverMissingAndNeverWritten(t *testing.T) {
	s := setup(t, `
variables:
  - name: PW
    title: Password
    type: secret
    required: true
`)
	// Required, unanswered, and still not what stops the program: a secret is
	// asked for immediately before the run that needs it, because it is never
	// written down and so would be missing at every single start.
	if got := s.Missing(); len(got) != 0 {
		t.Errorf("missing = %v, want a secret not to block", names(got))
	}
	if got := names(s.Secrets()); strings.Join(got, ",") != "PW" {
		t.Errorf("secrets = %v", got)
	}

	s.Set("PW", "hunter2")
	if err := s.Save(); err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(s.Path())
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(raw), "hunter2") || strings.Contains(string(raw), "PW") {
		t.Fatalf("the answer file mentions the secret:\n%s", raw)
	}
}

func TestForgetClearsSecrets(t *testing.T) {
	s := setup(t, "variables:\n  - name: PW\n    title: P\n    type: secret\n")
	s.Set("PW", "hunter2")
	s.Forget()
	if got := s.Get("PW"); got != "" {
		t.Errorf("PW = %q after Forget", got)
	}
}

// The answer file is shell and is meant to be opened in an editor, so every
// value has to survive the round trip whatever is in it.
func TestAnswersSurviveTheRoundTrip(t *testing.T) {
	values := map[string]string{
		"PLAIN":  "/dev/sda",
		"SPACED": "Europe/Berlin and elsewhere",
		"QUOTED": "it's a 'quoted' value",
		"HASHED": "value # not a comment",
		"EMPTY":  "",
		"DOLLAR": "$HOME and `backticks`",
	}
	var decl strings.Builder
	decl.WriteString("variables:\n")
	for name := range values {
		decl.WriteString("  - name: " + name + "\n    title: " + name + "\n")
	}
	s := setup(t, decl.String())
	for name, v := range values {
		s.Set(name, v)
	}
	if err := s.Save(); err != nil {
		t.Fatal(err)
	}

	// A second store over the same file, to prove the values come back from the
	// file rather than from memory.
	back := New(s.mod, s.Path())
	if err := back.Load(); err != nil {
		t.Fatal(err)
	}
	for name, want := range values {
		if got := back.Get(name); got != want {
			t.Errorf("%s = %q, want %q", name, got, want)
		}
	}
}

// The file is written to be sourceable, which is most of the reason it is shell
// and not yaml.
func TestTheAnswerFileIsValidShell(t *testing.T) {
	s := setup(t, twoVars)
	s.Set("USER", "it's me")
	if err := s.Save(); err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(s.Path())
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), `USER='it'\''s me'`) {
		t.Errorf("quoting is wrong:\n%s", raw)
	}
}

func TestALeftoverKeyIsNotAnError(t *testing.T) {
	s := setup(t, twoVars)
	body := "USER='moritz'\nGONE='from an older folder'\n# a comment\n\nHOST=\"quoted\"\n"
	if err := os.WriteFile(s.Path(), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := s.Load(); err != nil {
		t.Fatal(err)
	}
	if s.Get("USER") != "moritz" || s.Get("HOST") != "quoted" {
		t.Errorf("USER=%q HOST=%q", s.Get("USER"), s.Get("HOST"))
	}
}

func TestApplyingAPresetIsJustSettingValues(t *testing.T) {
	sp := load(t, "title: T\nstages: [go]\npresets:\n  - id: start\n    title: Start\n    options:\n      - id: full\n        title: Full\n        values:\n          HOST: server\n"+twoVars)
	s := New(sp, filepath.Join(t.TempDir(), "c"))
	s.Apply(sp.Presets[0].Options[0])
	if got := s.Get("HOST"); got != "server" {
		t.Errorf("HOST = %q", got)
	}
}

// Every declared variable reaches a script, answered or not, so a script may
// read one without first checking whether the question was ever asked.
func TestEveryVariableReachesAScript(t *testing.T) {
	s := setup(t, twoVars)
	s.SetFacts("1.0")
	s.Set("USER", "moritz")
	env := strings.Join(s.Env(), "\n")
	for _, want := range []string{"USER=moritz", "HOST=arch-os", "RUNTIME_VERSION=1.0", "MODULE_CONF="} {
		if !strings.Contains(env, want) {
			t.Errorf("env is missing %q", want)
		}
	}
}

// A variable that means nothing given the answers so far is neither asked for
// nor shown.
func TestConditionsHideQuestions(t *testing.T) {
	s := setup(t, `
variables:
  - name: DESKTOP
    title: Desktop
    type: bool
  - name: DRIVER
    title: Driver
    required: true
    conditions: DESKTOP == true
`)
	if got := s.Missing(); len(got) != 0 {
		t.Errorf("missing = %v with no desktop", names(got))
	}
	s.Set("DESKTOP", "true")
	if got := names(s.Missing()); strings.Join(got, ",") != "DRIVER" {
		t.Errorf("missing = %v with a desktop", got)
	}
}

// What comes first is the same rule as what is missing, narrowed — so a second
// start, where the answer is already in the file, goes straight past it.
func TestUpfrontIsWhatIsStillOpenAndMarkedFirst(t *testing.T) {
	s := setup(t, `
variables:
  - name: LOCALE
    title: Locale
    required: true
    first: true
  - name: USER
    title: User
    required: true
`)
	if got := names(s.Upfront()); strings.Join(got, ",") != "LOCALE" {
		t.Errorf("upfront = %v, want just LOCALE — USER is not marked first", got)
	}
	s.Set("LOCALE", "de_DE")
	if got := s.Upfront(); len(got) != 0 {
		t.Errorf("upfront = %v, want nothing left to ask on the way in", names(got))
	}
	if got := names(s.Missing()); strings.Join(got, ",") != "USER" {
		t.Errorf("missing = %v, want the opening run to still have USER", got)
	}
}

// The settings page reads true and false out loud wherever they turn up, so a
// list that offers a third answer beside them is still readable — and a
// question nobody has answered reads as a dash rather than as an empty column.
func TestDisplayReadsTheTwoBoolWordsOutLoud(t *testing.T) {
	s := setup(t, `
variables:
  - name: AUTOLOGIN
    title: Autologin
    values: [auto, true, false]
  - name: HOST
    title: Host
`)
	for value, want := range map[string]string{"auto": "auto", "true": "Yes", "false": "No"} {
		s.Set("AUTOLOGIN", value)
		if got := s.Display(s.mod.Var("AUTOLOGIN")); got != want {
			t.Errorf("display of %q = %q, want %q", value, got, want)
		}
	}
	if got := s.Display(s.mod.Var("HOST")); got != "—" {
		t.Errorf("display of nothing = %q, want a dash", got)
	}
}

func names(vs []*spec.Variable) []string {
	out := make([]string, len(vs))
	for i, v := range vs {
		out[i] = v.Name
	}
	return out
}

// An exported variable is what drives an unattended run, so a declared name set
// in the environment is taken as an answer — and a secret never is, because
// what a secret is for is not being carried around.
func TestTheEnvironmentAnswersDeclaredQuestions(t *testing.T) {
	t.Setenv("USER", "moritz")
	t.Setenv("HOST", "")
	t.Setenv("PW", "hunter2")
	s := setup(t, `
variables:
  - name: USER
    title: User
  - name: HOST
    title: Host
    default: arch-os
  - name: PW
    title: Password
    type: secret
`)
	s.LoadEnv()
	if got := s.Get("USER"); got != "moritz" {
		t.Errorf("USER = %q, want moritz from the environment", got)
	}
	if got := s.Get("HOST"); got != "arch-os" {
		t.Errorf("HOST = %q, want the default — an empty variable is not an answer", got)
	}
	if got := s.Get("PW"); got != "" {
		t.Errorf("PW = %q, want nothing — a secret is not taken from the environment", got)
	}
}

// The settings page is a promise that every row on it can be opened, so a value
// that means nothing yet is not on it.
func TestVisibleLeavesOutWhatCannotBeAnsweredFromThere(t *testing.T) {
	sp := load(t, `
title: T
stages: [go]
variables:
  - name: DISK
    title: Disk
  - name: SNAPSHOT
    title: Snapshot
    values: [a, b]
  - name: EXTRA
    title: Extra
    conditions: DISK == /dev/sda
`)
	// Being named by a task's `asks:` is what defers a variable; the module above
	// has no such task, so it is deferred here the way the loader would.
	s := New(sp, filepath.Join(t.TempDir(), "installer.conf"))

	if got := names(s.Visible()); strings.Join(got, ",") != "DISK,SNAPSHOT" {
		t.Errorf("visible = %v, want DISK and SNAPSHOT — EXTRA's condition does not hold", got)
	}
	s.Set("DISK", "/dev/sda")
	if got := names(s.Visible()); strings.Join(got, ",") != "DISK,SNAPSHOT,EXTRA" {
		t.Errorf("visible = %v, want EXTRA once its condition holds", got)
	}
}

// An answer file is what turns a first run into a return, and the question is
// asked once, before the interface opens.
func TestExistsSaysWhetherThisMachineHasAnsweredAnythingYet(t *testing.T) {
	s := setup(t, twoVars)
	if s.Exists() {
		t.Error("a machine that has answered nothing reports an answer file")
	}
	if err := s.Save(); err != nil {
		t.Fatal(err)
	}
	if !s.Exists() {
		t.Error("the answer file was written and is not found")
	}
}

// A script may answer questions by appending to the answer file — a shared
// configuration fetched from somewhere, a link a run has just produced — and
// what it wrote has to arrive without the program being restarted.
func TestLoadingAgainPicksUpWhatAScriptWroteIntoTheAnswerFile(t *testing.T) {
	s := setup(t, twoVars)
	if err := s.Save(); err != nil {
		t.Fatal(err)
	}
	f, err := os.OpenFile(s.Path(), os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.WriteString("USER='moritz'\n"); err != nil {
		t.Fatal(err)
	}
	f.Close()

	if got := s.Get("USER"); got != "" {
		t.Fatalf("USER = %q before loading again", got)
	}
	if err := s.Load(); err != nil {
		t.Fatal(err)
	}
	if got := s.Get("USER"); got != "moritz" {
		t.Errorf("USER = %q after loading again, want moritz", got)
	}
}

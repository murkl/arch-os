package runner

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/murkl/arch-os/runtime/internal/i18n"
	"github.com/murkl/arch-os/runtime/internal/spec"
	"github.com/murkl/arch-os/runtime/internal/store"
)

// What a test module's declaration is called: the runtime takes whichever yaml
// it finds in the folder, and these tests use the name the real ones use.
const treeFile = "installer.yaml"

// setup writes a module: installer.yaml from the given variables and tasks,
// plus whatever extra files a test asked for.
func setup(t *testing.T, variables string, tasks map[string]string) (*spec.Module, *store.Store, *Runner) {
	t.Helper()
	dir := t.TempDir()
	files := map[string]string{treeFile: "title: T\nstages: [go]\n" + variables}
	if len(tasks) == 0 {
		tasks = oneTask
	}
	for id, yaml := range tasks {
		files["tasks/"+id+"/task.yaml"] = yaml
		files["tasks/"+id+"/task.sh"] = "echo ran\n"
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
	st := store.New(sp, filepath.Join(t.TempDir(), "installer.conf"))
	return sp, st, New(sp, st)
}

var oneTask = map[string]string{"go": "name: Go\nstage: go\n"}

// A bool answers itself, in the interface's own language, so a folder never has
// to spell out what true and false are called.
func TestABoolOffersItsTwoAnswersInWords(t *testing.T) {
	i18n.Use("de", &i18n.Catalog{Messages: map[string]string{"Yes": "Ja", "No": "Nein"}})
	defer i18n.Use(i18n.SourceLang)

	sp, _, r := setup(t, "variables:\n  - name: X\n    title: X\n    type: bool\n", nil)
	got, err := r.Options(sp.Var("X"))
	if err != nil {
		t.Fatal(err)
	}
	want := []Option{{Value: "true", Label: "Ja"}, {Value: "false", Label: "Nein"}}
	if len(got) != 2 || got[0] != want[0] || got[1] != want[1] {
		t.Errorf("options = %+v, want %+v", got, want)
	}
}

func TestAWrittenOutSetIsItsOwnLabel(t *testing.T) {
	sp, _, r := setup(t, "variables:\n  - name: FS\n    title: FS\n    values: [btrfs, ext4]\n", nil)
	got, err := r.Options(sp.Var("FS"))
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].Value != "btrfs" || got[0].Label != "btrfs" {
		t.Errorf("options = %+v", got)
	}
}

// The one rule that lets a disk be stored as /dev/sda and chosen by its size.
func TestATabSeparatesTheValueStoredFromTheTextRead(t *testing.T) {
	sp, _, r := setup(t, `
variables:
  - name: DISK
    title: Disk
    command: printf '/dev/sda\t/dev/sda  1TB Samsung\n\tNone of these\nplain\n'
`, nil)
	got, err := r.Options(sp.Var("DISK"))
	if err != nil {
		t.Fatal(err)
	}
	want := []Option{
		{Value: "/dev/sda", Label: "/dev/sda  1TB Samsung"},
		// An empty value in front of the tab is a real answer, not a blank line.
		{Value: "", Label: "None of these"},
		// No tab at all: the value is its own label.
		{Value: "plain", Label: "plain"},
	}
	if len(got) != len(want) {
		t.Fatalf("options = %+v, want %+v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("option %d = %+v, want %+v", i, got[i], want[i])
		}
	}
}

// A suggestion is never worth stopping for.
func TestAPrefillThatFailsIsSimplyNoSuggestion(t *testing.T) {
	sp, _, r := setup(t, `
variables:
  - name: A
    title: A
    prefill: echo Europe/Berlin
  - name: B
    title: B
    prefill: exit 1
`, nil)
	if got := r.Prefill(sp.Var("A")); got != "Europe/Berlin" {
		t.Errorf("prefill = %q", got)
	}
	if got := r.Prefill(sp.Var("B")); got != "" {
		t.Errorf("failed prefill = %q, want nothing", got)
	}
}

// The list is a promise of what is about to happen, so a task that has
// ruled itself out is not in it.
func TestTasksAreOnlyTheOnesThatWillRun(t *testing.T) {
	_, st, r := setup(t, "variables:\n  - name: DESKTOP\n    title: D\n    type: bool\n", map[string]string{
		"always":  "name: Always\nstage: go\n",
		"desktop": "name: Desktop\nstage: go\nconditions: DESKTOP == true\n",
	})
	if got := names(r.Tasks()); strings.Join(got, ",") != "Always" {
		t.Errorf("tasks = %v", got)
	}
	st.Set("DESKTOP", "true")
	if got := names(r.Tasks()); strings.Join(got, ",") != "Always,Desktop" {
		t.Errorf("tasks = %v", got)
	}
}

func TestPreflightPassesWhenTheTreeHasNoHook(t *testing.T) {
	_, _, r := setup(t, "variables: []\n", nil)
	if err := r.Preflight(); err != nil {
		t.Errorf("err = %v", err)
	}
}

func TestPreflightCarriesWhatTheHookSaid(t *testing.T) {
	dir := t.TempDir()
	files := map[string]string{
		treeFile:             "title: T\nstages: [go]\nvariables: []\n",
		"tasks/go/task.yaml": "name: Go\nstage: go\n",
		"tasks/go/task.sh":   "true\n",
		"hooks/preflight.sh": "echo Set the boot mode to UEFI. >&2\nexit 1\n",
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
	st := store.New(sp, filepath.Join(t.TempDir(), "c"))
	err = New(sp, st).Preflight()
	if err == nil {
		t.Fatal("a failing check passed")
	}
	if !strings.Contains(err.Error(), "Set the boot mode to UEFI.") {
		t.Errorf("err = %q, want what the check said", err)
	}
}

func TestStartRunsAnTaskAndReportsIt(t *testing.T) {
	sp, _, r := setup(t, "variables: []\n", map[string]string{
		"good": "name: Good\nstage: go\n",
		"bad":  "name: Bad\nstage: go\nneeds: [good]\n",
	})
	// The failing one is written over the script setup laid down for it.
	if err := os.WriteFile(sp.Tasks[1].Path(), []byte("echo why not >&2\nexit 1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	good, err := r.Start(sp.Tasks[0])
	if err != nil {
		t.Fatal(err)
	}
	<-good.Done()
	if good.Err() != nil {
		t.Errorf("err = %v", good.Err())
	}

	bad, err := r.Start(sp.Tasks[1])
	if err != nil {
		t.Fatal(err)
	}
	<-bad.Done()
	if bad.Err() == nil {
		t.Fatal("a failing task was not reported")
	}
	if !strings.Contains(bad.Err().Error(), "why not") {
		t.Errorf("err = %q", bad.Err())
	}
}

func names(units []*spec.Task) []string {
	out := make([]string, len(units))
	for i, e := range units {
		out[i] = e.Name
	}
	return out
}

// An answer that changes the machine the installer is running on has to be put
// in force rather than only stored: a console keyboard nobody loaded is a
// layout nobody is typing on.
func TestApplyPutsAnAnswerInForce(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("DIR", dir)
	sp, st, r := setup(t, `
variables:
  - name: KEYMAP
    title: Keymap
    apply: echo "$KEYMAP" > "${DIR}/loaded"
  - name: PLAIN
    title: Plain
`, nil)
	st.Set("KEYMAP", "de-latin1")
	r.Apply(sp.Var("KEYMAP"))
	loaded, err := os.ReadFile(filepath.Join(dir, "loaded"))
	if err != nil {
		t.Fatalf("nothing was applied: %v", err)
	}
	if strings.TrimSpace(string(loaded)) != "de-latin1" {
		t.Errorf("applied %q, want the answer that was just given", loaded)
	}
	// A variable that declares none is simply not applied, and saying so is
	// cheaper than a nil check at every call site.
	r.Apply(sp.Var("PLAIN"))
}

// The answer stands whether or not it could be put in force: an installer that
// stops because a keymap would not load is worse than one carrying on.
func TestAnApplyThatFailsIsOnlyAWarning(t *testing.T) {
	sp, st, r := setup(t, "variables:\n  - name: X\n    title: X\n    apply: exit 1\n", nil)
	st.Set("X", "value")
	r.Apply(sp.Var("X"))
	if got := st.Get("X"); got != "value" {
		t.Errorf("X = %q, want the answer to stand", got)
	}
}

// Settle is what makes a second start on the same machine stand where the first
// one left off: the answers survived in the answer file and their effect on the
// live system did not.
func TestSettleAppliesOnlyTheAnswersThatWereGiven(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("DIR", dir)
	_, st, r := setup(t, `
variables:
  - name: GIVEN
    title: Given
    apply: touch "${DIR}/given"
  - name: OPEN
    title: Open
    apply: touch "${DIR}/open"
`, nil)
	st.Set("GIVEN", "de-latin1")
	r.Settle()
	if _, err := os.Stat(filepath.Join(dir, "given")); err != nil {
		t.Errorf("an answer this run started with was not put in force: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "open")); err == nil {
		t.Error("a question nobody has answered was applied")
	}
}

// true and false are the runtime's own two words wherever they turn up, so a
// list that offers a third answer beside them still reads as Yes and No.
func TestAListHoldingTrueAndFalseStillReadsInWords(t *testing.T) {
	i18n.Use("de", &i18n.Catalog{Messages: map[string]string{"Yes": "Ja", "No": "Nein"}})
	defer i18n.Use(i18n.SourceLang)

	sp, _, r := setup(t, "variables:\n  - name: X\n    title: X\n    values: [auto, true, false]\n", nil)
	got, err := r.Options(sp.Var("X"))
	if err != nil {
		t.Fatal(err)
	}
	want := []Option{{Value: "auto", Label: "auto"}, {Value: "true", Label: "Ja"}, {Value: "false", Label: "Nein"}}
	if len(got) != len(want) {
		t.Fatalf("options = %+v, want %+v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("option %d = %+v, want %+v", i, got[i], want[i])
		}
	}
}

// The starting point that fetches its answers: a shell writes them into the
// answer file, and the runner reads them back and puts them into force. This is
// the whole of how a shared configuration becomes an installation.
func TestAnImportedConfigurationBecomesTheAnswers(t *testing.T) {
	applied := filepath.Join(t.TempDir(), "applied")
	_, st, r := setup(t, "variables:\n"+
		"  - name: DISK\n    title: Disk\n"+
		"  - name: KEYMAP\n    title: Keymap\n    apply: touch \"$APPLIED\"\n", nil)
	t.Setenv("APPLIED", applied)
	st.SetFacts("test", false)

	shell := "printf \"DISK='/dev/sdz'\\nKEYMAP='de'\\n\" >>\"$MODULE_CONF\""
	if err := r.Import(shell)(); err != nil {
		t.Fatal(err)
	}
	if err := r.Imported(); err != nil {
		t.Fatal(err)
	}

	if got := st.Get("DISK"); got != "/dev/sdz" {
		t.Errorf("DISK = %q, want /dev/sdz", got)
	}
	if _, err := os.Stat(applied); err != nil {
		t.Error("the imported keymap was never applied to the live system")
	}
}

// What a shell says on stderr is what stands on the page, so a wrong code reads
// as a wrong code rather than as a number.
func TestAnImportThatFailsSaysWhy(t *testing.T) {
	_, _, r := setup(t, "variables:\n  - name: X\n    title: X\n", nil)
	err := r.Import("echo 'nothing is kept at that address' >&2; exit 1")()
	if err == nil {
		t.Fatal("a failing import reported success")
	}
	if !strings.Contains(err.Error(), "nothing is kept at that address") {
		t.Errorf("the message is %q", err)
	}
}

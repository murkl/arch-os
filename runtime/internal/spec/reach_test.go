package spec

import (
	"maps"
	"strings"
	"testing"
)

// The declaration every test here starts from: two questions, the second asked
// only where the first says there is a desktop at all.
const guarded = `title: Test Installer
stages: [go]
variables:
  - name: DESKTOP
    title: Desktop
    values: [gnome, none]
    required: true
  - name: EXTRAS
    title: Extras
    type: bool
    default: true
    conditions: DESKTOP != none
`

// consistent is that declaration with one task that reads both answers: guarded
// on the desktop, which is how it reads that one, and naming the other in its
// script. Nothing in it is unread, and each test below breaks exactly one thing.
func consistent(files map[string]string) map[string]string {
	out := map[string]string{
		treeFile: guarded,
		// The helper's own task, left out: these tests write their own.
		"tasks/do/task.yaml":      "",
		"tasks/do/task.sh":        "",
		"tasks/desktop/task.yaml": "name: Desktop\nstage: go\nconditions: DESKTOP == gnome\n",
		"tasks/desktop/task.sh":   "echo \"$EXTRAS\"\n",
	}
	maps.Copy(out, files)
	return out
}

// unread runs the check over a module and hands back what it found, as the lines
// a person would read.
func unread(t *testing.T, files map[string]string) []string {
	t.Helper()
	sp, err := Load(module(t, files))
	if err != nil {
		t.Fatal(err)
	}
	found, err := sp.Unread()
	if err != nil {
		t.Fatal(err)
	}
	out := make([]string, len(found))
	for i, u := range found {
		out[i] = u.String()
	}
	return out
}

// widened is the declaration with the guard taken off the second question, so
// it is asked whether there is a desktop or not.
var widened = strings.Replace(guarded, "    conditions: DESKTOP != none\n", "", 1)

func TestATreeWhoseGuardsAgreeReportsNothing(t *testing.T) {
	if got := unread(t, consistent(nil)); len(got) != 0 {
		t.Errorf("Unread() = %v, want nothing", got)
	}
}

func TestAQuestionAskedWhereItsOnlyTaskCannotRunIsReported(t *testing.T) {
	got := unread(t, consistent(map[string]string{treeFile: widened}))
	if len(got) != 1 {
		t.Fatalf("Unread() = %v, want one finding", got)
	}
	// What it says has to be enough to go and fix it: which question, which
	// task, and the condition that task carries and the question does not.
	for _, want := range []string{"EXTRAS", "tasks/desktop", "DESKTOP == gnome"} {
		if !strings.Contains(got[0], want) {
			t.Errorf("Unread() = %q, want it to name %q", got[0], want)
		}
	}
}

func TestAWrittenOutSetOfValuesSettlesTheGuard(t *testing.T) {
	// The consistent module is only consistent because DESKTOP has two values:
	// `!= none` over [gnome, none] is `== gnome`, so the task guarded on gnome
	// runs wherever the question is asked. Take the values away and the same
	// two guards no longer say the same thing.
	open := strings.Replace(guarded, "    values: [gnome, none]\n", "", 1)
	got := unread(t, consistent(map[string]string{treeFile: open}))
	if len(got) != 1 || !strings.Contains(got[0], "EXTRAS") {
		t.Errorf("Unread() = %v, want EXTRAS reported once the domain is open", got)
	}
}

func TestATaskGuardedOnTheAnswerItselfReadsIt(t *testing.T) {
	// `EXTRAS == true` is not a task that runs somewhere else — it is the
	// answer being acted on, which is the only way a bool ever is read.
	files := consistent(map[string]string{
		treeFile:                widened,
		"tasks/desktop/task.sh": "echo desktop\n",
	})
	maps.Copy(files, unit("extras", "name: Extras\nstage: go\nconditions: EXTRAS == true\n"))
	if got := unread(t, files); len(got) != 0 {
		t.Errorf("Unread() = %v, want nothing", got)
	}
}

func TestOneTaskThatCanRunAnywhereIsEnough(t *testing.T) {
	files := consistent(map[string]string{treeFile: widened})
	maps.Copy(files, unit("always", "name: Always\nstage: go\n"))
	files["tasks/always/task.sh"] = "echo \"$EXTRAS\"\n"
	if got := unread(t, files); len(got) != 0 {
		t.Errorf("Unread() = %v, want nothing: one task reads it wherever it is asked", got)
	}
}

func TestTheSharedLibraryReadsForEveryTask(t *testing.T) {
	files := consistent(map[string]string{
		treeFile:                widened,
		"tasks/desktop/task.sh": "echo desktop\n",
		"lib.sh":                "echo \"$EXTRAS\"\n",
	})
	if got := unread(t, files); len(got) != 0 {
		t.Errorf("Unread() = %v, want nothing: lib.sh runs whatever the answers say", got)
	}
}

func TestAQuestionNothingReadsAtAllIsReported(t *testing.T) {
	spare := guarded + "  - name: SPARE\n    title: Spare\n    type: bool\n    default: true\n"
	got := unread(t, consistent(map[string]string{treeFile: spare}))
	if len(got) != 1 || !strings.Contains(got[0], "SPARE") {
		t.Fatalf("Unread() = %v, want SPARE reported", got)
	}
	if !strings.Contains(got[0], "nothing in this module reads this answer") {
		t.Errorf("Unread() = %q, want it to say nothing reads it", got[0])
	}
}

func TestAValueATaskAsksForOrShowsIsReadByThatTask(t *testing.T) {
	// Neither ever appears as $NAME anywhere: one is a list the run stops to
	// put, the other a value the task writes into the answer file for the frame
	// to draw. Being named in task.yaml is the whole of how they are read.
	declared := guarded + `  - name: PICK
    title: Pick
    values: [a, b]
    required: true
  - name: LINK
    title: Link
`
	files := consistent(map[string]string{treeFile: declared})
	maps.Copy(files, unit("work", "name: Work\nstage: go\nasks: PICK\nshows: LINK\nreport: |\n  Done\n\n  It worked.\n"))
	if got := unread(t, files); len(got) != 0 {
		t.Errorf("Unread() = %v, want nothing", got)
	}
}

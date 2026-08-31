package spec

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// tree writes a minimal but complete installer tree and returns its path. Each
// test starts from a working one and breaks exactly the thing it is about, so a
// failure names the rule that was broken rather than a missing file three rules
// earlier.
//
// A file whose body is empty is left out, which is how a test removes one.
func tree(t *testing.T, files map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	base := map[string]string{
		FileInstaller:        head("variables:\n  - name: DISK\n    title: Disk\n    required: true\n"),
		"tasks/do/task.yaml": "name: Do it\nstage: go\n",
		"tasks/do/task.sh":   "echo hi\n",
	}
	for name, body := range files {
		base[name] = body
	}
	for name, body := range base {
		if body == "" {
			continue
		}
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

// head is an installer.yaml with the two keys every tree needs, and whatever
// the test is actually about after them.
func head(body string) string { return "title: Test Installer\nstages: [go]\n" + body }

// unit is one task folder, as the two files it is made of.
func unit(id, yaml string) map[string]string {
	return map[string]string{
		"tasks/" + id + "/task.yaml": yaml,
		"tasks/" + id + "/task.sh":   "echo " + id + "\n",
	}
}

// units merges several unit() results into the map a tree is written from.
func units(all ...map[string]string) map[string]string {
	out := map[string]string{}
	for _, m := range all {
		for k, v := range m {
			out[k] = v
		}
	}
	return out
}

func TestLoadReadsAWholeTree(t *testing.T) {
	dir := tree(t, map[string]string{
		FileInstaller: `
title: Test Installer
accent: "#1793d1"
confirm: Erasing {{DISK}}.
stages: [go, done]
variables:
  - name: DISK
    title: Disk
    required: true
presets:
  - id: start
    title: Start
    options:
      - id: full
        title: Full
        values:
          DISK: /dev/sda
`,
		"tasks/reboot/task.yaml": "name: Reboot\nstage: done\nconfirm: Restart now?\nquits: true\n",
		"tasks/reboot/task.sh":   "echo bye\n",
	})
	sp, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	if sp.UI.Title != "Test Installer" {
		t.Errorf("title = %q", sp.UI.Title)
	}
	// A tree that says nothing about modes has exactly one, holding the stages
	// and the warning it wrote at the top level.
	if len(sp.Modes) != 1 || sp.Asked() {
		t.Errorf("modes = %+v, want one and unasked", sp.Modes)
	}
	if got := sp.Modes[0].ConfirmText(func(string) string { return "/dev/sda" }); got != "Erasing /dev/sda." {
		t.Errorf("confirm = %q", got)
	}
	if len(sp.Presets) != 1 || sp.Presets[0].Options[0].Values["DISK"] != "/dev/sda" {
		t.Errorf("presets = %+v", sp.Presets)
	}
	if len(sp.Tasks) != 2 {
		t.Fatalf("tasks = %d, want 2", len(sp.Tasks))
	}
	if !strings.HasSuffix(sp.Tasks[0].Path(), filepath.Join("do", FileScript)) {
		t.Errorf("script = %q", sp.Tasks[0].Path())
	}
	last := sp.Tasks[1]
	if !last.Quits || !last.Confirms() {
		t.Errorf("reboot = %+v, want it to ask and to quit", last)
	}
	if got := last.Question(func(string) string { return "" }); got != "Restart now?" {
		t.Errorf("question = %q", got)
	}
}

// The order is worked out from what each task says about itself, and it is
// the one thing about a tree nobody writes down. Getting it wrong means
// installing onto a disk that has not been partitioned yet.
// A tree that does more than one thing: each mode owns its stages, and a task
// says which run it belongs to by naming one of them and nothing else.
func TestModesOwnTheirStagesAndTheTasksInThem(t *testing.T) {
	dir := tree(t, units(
		map[string]string{
			// The tree helper's own task belongs to neither mode's story here.
			"tasks/do/task.yaml": "",
			"tasks/do/task.sh":   "",
			FileInstaller: `
title: Test Installer
modes:
  - id: install
    title: Installation
    confirm: Erasing {{DISK}}.
    stages: [go, done]
  - id: repair
    title: Recovery
    confirm: Opening {{DISK}}.
    stages: [open]
variables:
  - name: DISK
    title: Disk
    required: true
  - name: SNAP
    title: Snapshot
    values: [one, two]
    mode: repair
`,
		},
		unit("a-install", "name: Install\nstage: go\n"),
		unit("b-finish", "name: Finish\nstage: done\n"),
		unit("c-repair", "name: Repair\nstage: open\nasks: SNAP\n"),
	))
	sp, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	if !sp.Asked() || len(sp.Modes) != 2 {
		t.Fatalf("modes = %+v, want two and a question about them", sp.Modes)
	}
	// The stages of every mode, in the order the modes were declared: one list,
	// so one order settles the whole tree.
	if got := strings.Join(sp.Stages, " "); got != "go done open" {
		t.Errorf("stages = %q", got)
	}
	want := map[string]string{"a-install": "install", "b-finish": "install", "c-repair": "repair"}
	for _, task := range sp.Tasks {
		if got := task.Mode(); got != want[task.ID()] {
			t.Errorf("%s is in mode %q, want %q", task.ID(), got, want[task.ID()])
		}
	}
	if got := sp.Mode("repair").ConfirmText(func(string) string { return "/dev/sda" }); got != "Opening /dev/sda." {
		t.Errorf("confirm = %q", got)
	}
	// A variable guarded by the mode is only a question in that mode.
	in := func(mode string) func(string) string {
		return func(name string) string {
			if name == ModeVar {
				return mode
			}
			return ""
		}
	}
	snap := sp.Var("SNAP")
	if snap.Applies(in("install")) || !snap.Applies(in("repair")) {
		t.Error("SNAP should belong to the repair mode alone")
	}
}

func TestOrderFollowsStagesThenNeeds(t *testing.T) {
	dir := tree(t, units(
		map[string]string{
			FileInstaller: "title: T\nstages: [first, second]\n",
			// The default task is removed: this test owns the whole list.
			"tasks/do/task.yaml": "name: Do\nstage: first\n",
		},
		unit("zulu", "name: Zulu\nstage: first\n"),
		unit("alpha", "name: Alpha\nstage: first\nneeds: [zulu]\n"),
		unit("later", "name: Later\nstage: second\n"),
	))
	sp, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	var ids []string
	for _, e := range sp.Tasks {
		ids = append(ids, e.ID())
	}
	// do and zulu are independent and keep folder order; alpha needs zulu, so
	// it waits for it even though its name would have put it first; later is in
	// the second stage and comes after all of them.
	want := "do|zulu|alpha|later"
	if strings.Join(ids, "|") != want {
		t.Errorf("order = %v, want %v", ids, strings.Split(want, "|"))
	}
}

func TestOrderRefusesWhatCannotBeWalked(t *testing.T) {
	cases := []struct {
		name  string
		files map[string]string
		want  string
	}{
		{
			name:  "a stage nothing declared",
			files: unit("do", "name: Do\nstage: nowhere\n"),
			want:  "no such stage",
		},
		{
			name:  "a need pointing at nothing",
			files: unit("do", "name: Do\nstage: go\nneeds: [ghost]\n"),
			want:  "needs unknown task",
		},
		{
			name: "a need on a later stage, which could never be waited for",
			files: units(
				map[string]string{FileInstaller: "title: T\nstages: [go, later]\n"},
				unit("do", "name: Do\nstage: go\nneeds: [after]\n"),
				unit("after", "name: After\nstage: later\n"),
			),
			want: "later stage",
		},
		{
			name: "two tasks waiting for each other",
			files: units(
				unit("do", "name: Do\nstage: go\nneeds: [other]\n"),
				unit("other", "name: Other\nstage: go\nneeds: [do]\n"),
			),
			want: "wait on each other",
		},
		{
			name:  "a task with no stage at all",
			files: unit("do", "name: Do\n"),
			want:  "stage is required",
		},
		{
			name:  "a task folder with no yaml in it",
			files: map[string]string{"tasks/half/task.sh": "echo\n"},
			want:  FileTask,
		},
		{
			name:  "a task yaml with no script beside it",
			files: map[string]string{"tasks/half/task.yaml": "name: Half\nstage: go\n"},
			want:  "missing " + FileScript,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Load(tree(t, tc.files))
			if err == nil {
				t.Fatalf("loaded a tree with %s", tc.name)
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Errorf("error = %q, want it to mention %q", err, tc.want)
			}
		})
	}
}

// Nothing declares the hooks: a script in hooks/ under a name the runtime
// knows is the declaration, and every other name there is a typo rather than
// something to ignore.
func TestHooksAreFoundByTheirName(t *testing.T) {
	sp, err := Load(tree(t, map[string]string{
		"hooks/" + HookPreflight + ScriptExt: "exit 0\n",
		"hooks/" + HookRestart + ScriptExt:   "reboot\n",
	}))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(sp.Hook(HookPreflight), "preflight.sh") {
		t.Errorf("preflight hook = %q", sp.Hook(HookPreflight))
	}
	if got := Source(sp.Hook(HookRestart)); !strings.HasPrefix(got, "source ") {
		t.Errorf("Source() = %q, want it to source the file", got)
	}
	if sp.Hook(HookShutdown) != "" {
		t.Errorf("shutdown hook = %q, want none", sp.Hook(HookShutdown))
	}
	if !sp.Leaves() {
		t.Error("Leaves() = false, want true: there is a restart hook")
	}
}

func TestATreeWithoutHooksHasNone(t *testing.T) {
	sp, err := Load(tree(t, nil))
	if err != nil {
		t.Fatal(err)
	}
	for _, name := range HookNames {
		if sp.Hook(name) != "" {
			t.Errorf("%s = %q, want none", name, sp.Hook(name))
		}
	}
	if sp.Leaves() {
		t.Error("Leaves() = true, want false: nothing says how to leave")
	}
}

// lib.sh and locales/ are found the same way, so a tree turns them on by
// having them and off by not.
func TestLibAndLocalesAreFoundBesideTheInstallerFile(t *testing.T) {
	sp, err := Load(tree(t, map[string]string{
		FileLib:                 "helper() { echo hi; }\n",
		DirLocales + "/de.yaml": "language: Deutsch\n",
	}))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(sp.Lib, FileLib) {
		t.Errorf("lib = %q", sp.Lib)
	}
	if !strings.HasSuffix(sp.Locales, DirLocales) {
		t.Errorf("locales = %q", sp.Locales)
	}

	if sp, err = Load(tree(t, nil)); err != nil {
		t.Fatal(err)
	}
	if sp.Lib != "" || sp.Locales != "" {
		t.Errorf("lib = %q, locales = %q, want neither", sp.Lib, sp.Locales)
	}
}

// The sentence read on the way out is the tree's, so it is translated like
// everything else it says.
func TestConsoleIsTranslatable(t *testing.T) {
	sp, err := Load(tree(t, map[string]string{
		FileInstaller: head("console: Type installer to start again.\n"),
	}))
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"Test Installer", "Type installer to start again.", "Do it"}
	if strings.Join(sp.Strings(), "|") != strings.Join(want, "|") {
		t.Errorf("Strings() = %v\nwant %v", sp.Strings(), want)
	}
}

// Every one of these is an authoring mistake that must be caught while the tree
// is being opened. The alternative — loading anyway — is a task that
// silently never runs on somebody's machine, which is the failure this whole
// check exists to prevent.
func TestLoadRefuses(t *testing.T) {
	cases := []struct {
		name  string
		files map[string]string
		want  string
	}{
		{
			name:  "a condition naming a variable nobody declared",
			files: unit("do", "name: Do\nstage: go\nconditions: NOPE == true\n"),
			want:  "no such variable",
		},
		{
			name:  "a condition that is not three words",
			files: unit("do", "name: Do\nstage: go\nconditions: DISK\n"),
			want:  "bad condition",
		},
		{
			name:  "a task with no name",
			files: unit("do", "stage: go\n"),
			want:  "name is required",
		},
		{
			name:  "an offer opening on an answer it does not have",
			files: unit("do", "name: Do\nstage: go\nconfirm: Really?\ndefault: maybe\n"),
			want:  "yes or no",
		},
		{
			name:  "an answer to an offer that was never made",
			files: unit("do", "name: Do\nstage: go\ndefault: no\n"),
			want:  "no confirm for it to answer",
		},
		{
			name:  "a preset filling in a variable nobody declared",
			files: map[string]string{FileInstaller: head("presets:\n  - id: p\n    title: P\n    options:\n      - id: o\n        title: O\n        values:\n          NOPE: x\n")},
			want:  "no such variable",
		},
		{
			name:  "a preset page with nothing to choose on it",
			files: map[string]string{FileInstaller: head("presets:\n  - id: p\n    title: P\n")},
			want:  "no options",
		},
		{
			name:  "a preset option with no title",
			files: map[string]string{FileInstaller: head("presets:\n  - id: p\n    title: P\n    options:\n      - id: o\n")},
			want:  "title is required",
		},
		{
			name:  "two variables of the same name",
			files: map[string]string{FileInstaller: head("variables:\n  - name: DISK\n    title: A\n  - name: DISK\n    title: B\n")},
			want:  "declared twice",
		},
		{
			name:  "a variable with no title",
			files: map[string]string{FileInstaller: head("variables:\n  - name: DISK\n")},
			want:  "title is required",
		},
		{
			name:  "a type nobody has heard of",
			files: map[string]string{FileInstaller: head("variables:\n  - name: DISK\n    title: D\n    type: colour\n")},
			want:  "unknown type",
		},
		{
			name:  "a bool with values of its own",
			files: map[string]string{FileInstaller: head("variables:\n  - name: DISK\n    title: D\n    type: bool\n    values: [a, b]\n")},
			want:  "has no values of its own",
		},
		{
			name:  "a secret asked first, which is a question that would never be asked",
			files: map[string]string{FileInstaller: head("variables:\n  - name: PW\n    title: P\n    type: secret\n    first: true\n")},
			want:  "cannot also be asked first",
		},
		{
			name:  "blind on a question that is not asked first",
			files: map[string]string{FileInstaller: head("variables:\n  - name: KEYMAP\n    title: K\n    blind: true\n    values: [us, de]\n")},
			want:  "blind only matters for a question asked first",
		},
		{
			name:  "a secret with a default, which would be a stored password",
			files: map[string]string{FileInstaller: head("variables:\n  - name: PW\n    title: P\n    type: secret\n    default: hunter2\n")},
			want:  "cannot have a default",
		},
		{
			name:  "both a list and a command for the same question",
			files: map[string]string{FileInstaller: head("variables:\n  - name: DISK\n    title: D\n    values: [a]\n    command: ls\n")},
			want:  "two answers to the same question",
		},
		{
			name:  "a pattern that is not a pattern",
			files: map[string]string{FileInstaller: head("variables:\n  - name: DISK\n    title: D\n    pattern: '['\n")},
			want:  "pattern",
		},
		{
			name:  "a key that is a typo, silently ignored by a lesser reader",
			files: map[string]string{FileInstaller: head("variables:\n  - name: DISK\n    title: D\n    requird: true\n")},
			want:  "field requird not found",
		},
		{
			name:  "a key that is a typo in a task",
			files: unit("do", "name: Do\nstage: go\nquites: true\n"),
			want:  "field quites not found",
		},
		{
			name:  "a language tied to a variable nobody declared",
			files: map[string]string{FileInstaller: head("language: NOPE\nvariables:\n  - name: DISK\n    title: D\n")},
			want:  "no such variable",
		},
		{
			name:  "the runtime's own variable, redeclared",
			files: map[string]string{FileInstaller: head("variables:\n  - name: " + LangVar + "\n    title: L\n")},
			want:  "belongs to the runtime",
		},
		{
			name:  "an accent that is not a colour",
			files: map[string]string{FileInstaller: "title: T\nstages: [go]\naccent: blue\n"},
			want:  "accent must be",
		},
		{
			name:  "no stages at all",
			files: map[string]string{FileInstaller: "title: T\nstages: []\n"},
			want:  "no stages",
		},
		{
			name:  "a stage listed twice",
			files: map[string]string{FileInstaller: "title: T\nstages: [go, go]\n"},
			want:  "listed twice",
		},
		{
			name:  "a mode with no id",
			files: map[string]string{FileInstaller: "title: T\nmodes:\n  - title: Go\n    stages: [go]\n"},
			want:  "a mode needs an id",
		},
		{
			name:  "a mode with no stages of its own",
			files: map[string]string{FileInstaller: "title: T\nmodes:\n  - id: a\n    title: A\n"},
			want:  "no stages",
		},
		{
			name:  "one stage claimed by two modes, so a task could not say which it is in",
			files: map[string]string{FileInstaller: "title: T\nmodes:\n  - id: a\n    title: A\n    stages: [go]\n  - id: b\n    title: B\n    stages: [go]\n"},
			want:  "already belongs to mode",
		},
		{
			name:  "stages at the top level as well as in the modes",
			files: map[string]string{FileInstaller: "title: T\nstages: [go]\nmodes:\n  - id: a\n    title: A\n    stages: [go]\n"},
			want:  "belong to a mode",
		},
		{
			name:  "a question belonging to a mode the tree does not offer",
			files: map[string]string{FileInstaller: head("variables:\n  - name: DISK\n    title: D\n    mode: nope\n")},
			want:  "no such mode",
		},
		{
			name:  "a question asked first and claimed by a mode, which is before there is one",
			files: map[string]string{FileInstaller: "title: T\nmodes:\n  - id: a\n    title: A\n    stages: [go]\nvariables:\n  - name: K\n    title: K\n    first: true\n    mode: a\n"},
			want:  "before there is a mode",
		},
		{
			name:  "asks naming a variable nobody declared",
			files: unit("do", "name: Do\nstage: go\nasks: NOPE\n"),
			want:  "no such variable",
		},
		{
			name:  "asks on a free text value, which is not a question the frame can put mid-run",
			files: unit("do", "name: Do\nstage: go\nasks: DISK\n"),
			want:  "no answers to choose from",
		},
		{
			name: "asks on a secret, which is already asked at the only safe moment",
			files: units(
				map[string]string{FileInstaller: head("variables:\n  - name: PW\n    title: P\n    type: secret\n")},
				unit("do", "name: Do\nstage: go\nasks: PW\n"),
			),
			want: "is a secret",
		},
		{
			name:  "a value shown on a page that does not exist",
			files: unit("do", "name: Do\nstage: go\nshows: DISK\n"),
			want:  "no report for it to appear on",
		},
		{
			name:  "a report showing a variable nobody declared",
			files: unit("do", "name: Do\nstage: go\nreport: Done\nshows: NOPE\n"),
			want:  "no such variable",
		},
		{
			name: "a report showing a secret",
			files: units(
				map[string]string{FileInstaller: head("variables:\n  - name: PW\n    title: Password\n    type: secret\n")},
				unit("do", "name: Do\nstage: go\nreport: Done\nshows: PW\n"),
			),
			want: "is a secret",
		},
		{
			name:  "a starting point asking for a variable nobody declared",
			files: map[string]string{FileInstaller: head("presets:\n  - id: p\n    title: P\n    options:\n      - id: o\n        title: O\n        asks: NOPE\n")},
			want:  "no such variable",
		},
		{
			name:  "a starting point with shell and nothing to run it on",
			files: map[string]string{FileInstaller: head("presets:\n  - id: p\n    title: P\n    options:\n      - id: o\n        title: O\n        apply: echo hi\n")},
			want:  "no asks for it to work from",
		},
		{
			name:  "a hook whose name is a typo",
			files: map[string]string{"hooks/preflght.sh": "exit 0\n"},
			want:  "not a hook",
		},
		{
			name:  "a hook with no .sh after it",
			files: map[string]string{"hooks/preflight": "exit 0\n"},
			want:  "not a hook",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Load(tree(t, tc.files))
			if err == nil {
				t.Fatalf("loaded a tree with %s", tc.name)
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Errorf("error = %q, want it to mention %q", err, tc.want)
			}
		})
	}
}

func TestConditionsDecideWhatBelongs(t *testing.T) {
	dir := tree(t, units(
		map[string]string{
			FileInstaller:        head("variables:\n  - name: DESKTOP\n    title: Desktop\n    type: bool\n"),
			"tasks/do/task.yaml": "name: Always\nstage: go\n",
		},
		unit("with", "name: Only with a desktop\nstage: go\nconditions: DESKTOP == true\n"),
		unit("without", "name: Only without one\nstage: go\nconditions: DESKTOP != true\n"),
	))
	sp, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct{ desktop, want string }{
		{"true", "Only with a desktop"},
		{"false", "Only without one"},
		{"", "Only without one"},
	} {
		// Only the one variable answers, the way a store does: everything else,
		// the mode this run is in included, is empty.
		get := func(name string) string {
			if name == "DESKTOP" {
				return tc.desktop
			}
			return ""
		}
		var names []string
		for _, e := range sp.Tasks {
			if e.Applies(get) {
				names = append(names, e.Name)
			}
		}
		want := []string{"Always", tc.want}
		if strings.Join(names, "|") != strings.Join(want, "|") {
			t.Errorf("DESKTOP=%q ran %v, want %v", tc.desktop, names, want)
		}
	}
}

// A shell field takes either the shell itself or the file it lives in, and the
// whole rule is the ./ in front. Getting this wrong either way is silent: a
// path run as a command, or a command looked for as a file.
func TestShellFieldsTellCodeFromFiles(t *testing.T) {
	dir := tree(t, map[string]string{
		FileInstaller: head(`
variables:
  - name: DISK
    title: Disk
    command: ./data/disks.sh
    prefill: lsblk -dno PATH | head -n1
`),
		"data/disks.sh": "lsblk\n",
	})
	sp, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	v := sp.Var("DISK")
	if !strings.HasPrefix(v.Command, "source ") || !strings.Contains(v.Command, "disks.sh") {
		t.Errorf("command = %q, want it to source the file", v.Command)
	}
	if v.Prefill != "lsblk -dno PATH | head -n1" {
		t.Errorf("prefill = %q, want it left as written", v.Prefill)
	}
}

func TestReflowKeepsOnlyTheBreaksThatWereMeant(t *testing.T) {
	dir := tree(t, map[string]string{
		FileInstaller: head("variables:\n  - name: DISK\n    title: Disk\n    description: |\n      One sentence\n      wrapped by an editor.\n\n      A second paragraph.\n"),
	})
	sp, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	want := "One sentence wrapped by an editor.\n\nA second paragraph."
	if got := sp.Var("DISK").Description; got != want {
		t.Errorf("description = %q, want %q", got, want)
	}
}

func TestExpandFillsInAnswers(t *testing.T) {
	get := func(name string) string {
		return map[string]string{"DISK": "/dev/sda"}[name]
	}
	for _, tc := range []struct{ in, want string }{
		{"Erasing {{DISK}}.", "Erasing /dev/sda."},
		{"Erasing {{ DISK }}.", "Erasing /dev/sda."},
		{"Nothing to fill in.", "Nothing to fill in."},
		{"{{DISK}} and {{DISK}}", "/dev/sda and /dev/sda"},
		// A name nothing answers is left empty rather than left as its own
		// braces, which would put the machinery on screen.
		{"On {{UNKNOWN}}.", "On ."},
		{"An {{unclosed", "An {{unclosed"},
	} {
		if got := Expand(tc.in, get); got != tc.want {
			t.Errorf("Expand(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

// Every answer is a string in the end, but nobody writes `default: "true"`.
func TestScalarReadsWhateverShapeItWasWrittenIn(t *testing.T) {
	dir := tree(t, map[string]string{
		FileInstaller: head("variables:\n  - name: A\n    title: A\n    default: true\n  - name: B\n    title: B\n    default: 8\n  - name: C\n    title: C\n    default: pc105\n"),
	})
	sp, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	for name, want := range map[string]string{"A": "true", "B": "8", "C": "pc105"} {
		if got := sp.Var(name).Default.String(); got != want {
			t.Errorf("%s default = %q, want %q", name, got, want)
		}
	}
}

func TestStringsIsEveryWordTheTreeSays(t *testing.T) {
	dir := tree(t, map[string]string{
		FileInstaller: head(`
confirm: Careful.
presets:
  - id: p
    title: Setup
    description: What kind.
    options:
      - id: o
        title: Full
        description: Everything.
variables:
  - name: DISK
    title: Disk
    description: Where it goes.
    group: Storage
    error: Pick one.
`),
		"tasks/do/task.yaml": "name: Do it\nstage: go\nconfirm: Really?\n",
	})
	sp, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"Test Installer", "Careful.", "Setup", "What kind.", "Full", "Everything.", "Disk", "Where it goes.", "Storage", "Pick one.", "Do it", "Really?"}
	got := sp.Strings()
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Errorf("Strings() = %v\nwant %v", got, want)
	}
}

func TestFindTakesAnInstallerItIsPointedAt(t *testing.T) {
	dir := tree(t, nil)
	got, err := Find(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got != dir {
		t.Errorf("Find(%q) = %q", dir, got)
	}
}

// Beside the binary and nowhere else. The test binary has no installer.yaml
// next to it, which is exactly the case a user hits when they copy the program
// out of the folder it belongs to.
func TestFindSaysWhereTheInstallerHasToBe(t *testing.T) {
	t.Chdir(tree(t, nil))
	_, err := Find("")
	if err == nil {
		t.Fatal("found an installer beside the test binary")
	}
	if !strings.Contains(err.Error(), FileInstaller) {
		t.Errorf("error = %q, want it to name %s", err, FileInstaller)
	}
}

// One guard is a line and several are a list, and every one of them has to
// hold: a row that belongs under two unrelated circumstances is two rows.
func TestSeveralConditionsAllHaveToHold(t *testing.T) {
	dir := tree(t, map[string]string{
		FileInstaller:        head("variables:\n  - name: DESKTOP\n    title: D\n    type: bool\n  - name: DRIVER\n    title: G\n"),
		"tasks/do/task.yaml": "name: Driver\nstage: go\nconditions:\n  - DESKTOP == true\n  - DRIVER != none\n",
	})
	sp, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		desktop, driver string
		want            bool
	}{
		{"true", "mesa", true},
		{"true", "none", false},
		{"false", "mesa", false},
		{"false", "none", false},
	} {
		get := func(name string) string {
			return map[string]string{"DESKTOP": tc.desktop, "DRIVER": tc.driver}[name]
		}
		if got := sp.Tasks[0].Applies(get); got != tc.want {
			t.Errorf("DESKTOP=%s DRIVER=%s applies = %v, want %v", tc.desktop, tc.driver, got, tc.want)
		}
	}
}

func TestConditionsRefuseAnythingButAConditionOrAListOfThem(t *testing.T) {
	_, err := Load(tree(t, unit("do", "name: Do\nstage: go\nconditions:\n  DISK: yes\n")))
	if err == nil || !strings.Contains(err.Error(), "conditions takes a condition") {
		t.Errorf("err = %v", err)
	}
}

// A value a task shows and one a starting point asks for are both values the
// opening run of questions has no business asking: the first does not exist yet
// and the second stands for nothing once it has been used. Nothing declares
// that — being named is the declaration.
func TestBeingNamedIsWhatDefersAValue(t *testing.T) {
	dir := tree(t, units(
		map[string]string{
			FileInstaller: head(`presets:
  - id: p
    title: P
    options:
      - id: o
        title: O
        asks: SOURCE
        apply: echo hi
variables:
  - name: DISK
    title: Disk
    required: true
  - name: LINK
    title: Shared at
  - name: SOURCE
    title: Configuration code
`),
		},
		unit("do", "name: Do\nstage: go\nreport: Done\nshows: LINK\n"),
	))
	sp, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"LINK", "SOURCE"} {
		if !sp.Var(name).Deferred() {
			t.Errorf("%s is not deferred", name)
		}
	}
	if sp.Var("DISK").Deferred() {
		t.Error("an ordinary question was deferred")
	}
}

// The first paragraph of a report is its headline, the way the first block of
// the opening logo is its eyebrow — one idiom, and nothing extra to declare.
func TestAReportsFirstParagraphIsItsHeadline(t *testing.T) {
	dir := tree(t, unit("do", "name: Do\nstage: go\nreport: |\n  Installed on {{DISK}}\n\n  And here is what that means.\n"))
	sp, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	answers := func(string) string { return "/dev/sda" }
	headline, body := sp.Tasks[0].ReportText(answers)
	if headline != "Installed on /dev/sda" {
		t.Errorf("headline = %q", headline)
	}
	if body != "And here is what that means." {
		t.Errorf("body = %q", body)
	}
	// A report of one paragraph is a headline and nothing else.
	if !sp.Tasks[0].Reports() {
		t.Error("a task with a report says it has none")
	}
}

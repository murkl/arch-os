package tui

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"installer/internal/i18n"
	"installer/internal/runner"
	"installer/internal/spec"
	"installer/internal/store"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// What a test tree's declaration is called: the runtime takes whichever yaml it
// finds in the folder, and these tests use the name the real trees use.
const treeFile = "installer.yaml"

// A whole program, driven by keystrokes, with a folder written for the test.
//
// The interface is tested the way it is used: press keys, read the screen. What
// is asserted is what a person would see, so a refactor that keeps the
// behaviour keeps the tests.

type harness struct {
	t    *testing.T
	m    *Model
	a    *app
	msgs chan tea.Msg
}

// The tree every flow test starts from: one page of presets, a handful of
// questions, three tasks, one of them conditional.
const testInstaller = `
title: Test Installer
confirm: Erasing {{DISK}}.
stages: [go, finish]
presets:
  - id: system
    title: Setup
    description: Choose what kind of system to install.
    options:
      - id: full
        title: Full
        description: Everything at once.
        values:
          EXTRAS: "true"
      - id: bare
        title: Bare
        description: Nothing at all.
        values:
          EXTRAS: "false"
variables:
  - name: USER
    title: User name
    description: The account you log in with.
    group: Identity
    required: true
    pattern: '^[a-z]+$'
    error: Lower case letters only.
  - name: PW
    title: Password
    type: secret
    required: true
  - name: DISK
    title: Disk
    group: Storage
    required: true
    command: printf '/dev/sda\t/dev/sda  1TB\n/dev/sdb\t/dev/sdb  2TB\n'
  - name: EXTRAS
    title: Extras
    group: Storage
    type: bool
  - name: DRIVER
    title: Driver
    values: [mesa, nvidia]
    required: true
    conditions: EXTRAS == true
`

// The three tasks, as the files they are made of.
var testTasks = map[string]string{
	"tasks/a-first/task.yaml":  "name: First\nstage: go\n",
	"tasks/a-first/task.sh":    "echo ran\n",
	"tasks/b-second/task.yaml": "name: Second\nstage: go\n",
	"tasks/b-second/task.sh":   "echo ran\n",
	"tasks/c-extras/task.yaml": "name: Only with extras\nstage: go\nconditions: EXTRAS == true\n",
	"tasks/c-extras/task.sh":   "echo ran\n",
}

func newHarness(t *testing.T, files map[string]string) *harness {
	t.Helper()
	i18n.Use(i18n.SourceLang)

	dir := t.TempDir()
	base := map[string]string{treeFile: testInstaller}
	for name, body := range testTasks {
		base[name] = body
	}
	for name, body := range files {
		base[name] = body
	}
	for name, body := range base {
		// An empty body is how a test leaves one of the standard files out.
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
	sp, err := spec.Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	st := store.New(sp, filepath.Join(t.TempDir(), "installer.conf"))
	st.SetFacts("test")
	// The catalogs the tree brought, discovered the way the program discovers
	// them — so a test that writes one is testing the thing that ships.
	var sources []fs.FS
	if sp.Locales != "" {
		sources = append(sources, os.DirFS(sp.Locales))
	}
	a := &app{
		spec: sp, store: st, runner: runner.New(sp, st), version: "test",
		langs: i18n.Discover(sources...), sources: sources,
		first: true,
	}
	h := &harness{t: t, a: a, msgs: make(chan tea.Msg, 64)}
	h.m = newModel(a, "")
	h.run(h.m.Init())
	h.drain()
	return h
}

// The loop, as the real program runs it: a command goes off on its own and
// whatever it produces comes back as a message. Nothing here waits on a
// command, because some of them are clocks that fire in half a second and one
// of them is an installation.
func (h *harness) run(cmd tea.Cmd) {
	if cmd == nil {
		return
	}
	go func() {
		if msg := cmd(); msg != nil {
			h.msgs <- msg
		}
	}()
}

// quiet is how long the loop waits with nothing arriving before it takes the
// interface to have settled.
const quiet = 60 * time.Millisecond

// drain handles everything waiting, and everything that arrives while it is
// handling it, until nothing has for a moment.
func (h *harness) drain() {
	for {
		select {
		case msg := <-h.msgs:
			switch msg := msg.(type) {
			case tea.BatchMsg:
				for _, c := range msg {
					h.run(c)
				}
			case tickMsg, spinMsg, animMsg:
				// A clock. It carries nothing and re-arms itself, so handling
				// one would be a test that never ends.
			default:
				if blink(msg) {
					continue
				}
				m, cmd := h.m.Update(msg)
				h.m = m.(*Model)
				h.run(cmd)
			}
		case <-time.After(quiet):
			return
		}
	}
}

// blink reports whether a message is a text cursor asking to be redrawn — the
// other clock in the program, and the only one this file cannot name outright
// because the type behind it is not exported.
func blink(msg tea.Msg) bool {
	return strings.HasPrefix(fmt.Sprintf("%T", msg), "cursor.")
}

func (h *harness) send(msg tea.Msg) *harness {
	h.t.Helper()
	m, cmd := h.m.Update(msg)
	h.m = m.(*Model)
	h.run(cmd)
	h.drain()
	return h
}

// restart is this machine started a second time: the answers are where the last
// run left them, and the program is asked again what there is to show.
func (h *harness) restart() *harness {
	h.t.Helper()
	h.a.first = false
	h.m = newModel(h.a, "")
	h.run(h.m.Init())
	h.drain()
	return h
}

func (h *harness) key(k tea.KeyType) *harness {
	h.send(tea.KeyMsg{Type: k})
	return h
}

func (h *harness) enter() *harness { return h.key(tea.KeyEnter) }
func (h *harness) down() *harness  { return h.key(tea.KeyDown) }
func (h *harness) esc() *harness   { return h.key(tea.KeyEsc) }
func (h *harness) ctrlC() *harness { return h.key(tea.KeyCtrlC) }

func (h *harness) typeIn(s string) *harness {
	h.t.Helper()
	for _, r := range s {
		h.send(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{r}})
	}
	return h
}

// screen is what is on it, as plain text.
func (h *harness) screen() string { return h.m.View() }

func (h *harness) wants(fragments ...string) *harness {
	h.t.Helper()
	view := h.screen()
	for _, want := range fragments {
		if !strings.Contains(view, want) {
			h.t.Fatalf("the screen does not show %q:\n%s", want, view)
		}
	}
	return h
}

func (h *harness) refuses(fragments ...string) *harness {
	h.t.Helper()
	view := h.screen()
	for _, unwanted := range fragments {
		if strings.Contains(view, unwanted) {
			h.t.Fatalf("the screen shows %q and should not:\n%s", unwanted, view)
		}
	}
	return h
}

// ran waits for a run to finish and for its result to become answerable. It is
// the one thing here that is genuinely worth waiting for: the stages are real
// processes, and the pause afterwards is what stops a keystroke meant for
// something else from dismissing the result.
func (h *harness) ran() *harness {
	h.t.Helper()
	deadline := time.Now().Add(20 * time.Second)
	for time.Now().Before(deadline) {
		if r, ok := h.m.top().(*runScreen); ok && r.settled {
			return h
		}
		h.drain()
	}
	h.t.Fatalf("the run never settled; the page on top is %T", h.m.top())
	return h
}

// asked waits for the run to stop at a task that asks first, and for its
// question to become answerable.
func (h *harness) asked() *harness {
	h.t.Helper()
	deadline := time.Now().Add(20 * time.Second)
	for time.Now().Before(deadline) {
		if r, ok := h.m.top().(*runScreen); ok && r.asking != nil && r.settled {
			return h
		}
		h.drain()
	}
	h.t.Fatalf("no question was ever asked; the page on top is %T", h.m.top())
	return h
}

// askedFor waits for the run to stop at a task that needs a value, with its
// answers fetched and its question answerable.
func (h *harness) askedFor() *harness {
	h.t.Helper()
	deadline := time.Now().Add(20 * time.Second)
	for time.Now().Before(deadline) {
		if r, ok := h.m.top().(*runScreen); ok && r.ask != nil && !r.ask.loading && r.settled {
			return h
		}
		h.drain()
	}
	h.t.Fatalf("nothing was ever asked for; the page on top is %T", h.m.top())
	return h
}

// reported waits for the run to stop on something it has to say, and for that
// page to become answerable.
func (h *harness) reported() *harness {
	h.t.Helper()
	deadline := time.Now().Add(20 * time.Second)
	for time.Now().Before(deadline) {
		if r, ok := h.m.top().(*runScreen); ok && r.told != nil && r.settled {
			return h
		}
		h.drain()
	}
	h.t.Fatalf("nothing was ever reported; the page on top is %T", h.m.top())
	return h
}

// answered waits for a question with shell hanging on it to have run that shell
// and come back — either onto the next page, or onto the same one with the
// reason it would not work.
func (h *harness) answered() *harness {
	h.t.Helper()
	deadline := time.Now().Add(20 * time.Second)
	for time.Now().Before(deadline) {
		if f, ok := h.m.top().(*fieldScreen); !ok || !f.busy {
			return h
		}
		h.drain()
	}
	h.t.Fatalf("the answer was never made good on")
	return h
}

// ─── What comes first ────────────────────────────────────────────────────────

// The one thing that cannot wait for the opening run of questions: a question
// marked `first` is asked before the network screen, because the passphrase
// typed into that screen is already typed on the keyboard this answer settles.
func TestAFirstQuestionIsAskedBeforeTheNetwork(t *testing.T) {
	h := newHarness(t, map[string]string{
		treeFile: testInstaller +
			"  - name: LOCALE\n    title: Language and formats\n    required: true\n    first: true\n    values: [de, en]\n",
		"hooks/online.sh": "exit 1\n",
	})
	h.wants("Language and formats", "de", "en").refuses("Wireless network", "internet connection")

	// Answered, and only now is there a network to look for.
	h.enter()
	h.wants("There is no internet connection.")
	if got := h.a.store.Get("LOCALE"); got != "de" {
		t.Errorf("LOCALE = %q, want the answer given before the network", got)
	}
}

// And the point of asking it first: answering it puts it in force there and
// then, before the page after it is on screen to be typed into.
func TestAnsweringAFirstQuestionPutsItInForce(t *testing.T) {
	loaded := filepath.Join(t.TempDir(), "loaded")
	h := newHarness(t, map[string]string{
		treeFile: testInstaller +
			"  - name: LOCALE\n    title: Language and formats\n    required: true\n    first: true\n" +
			"    values: [de, en]\n    apply: echo \"$LOCALE\" > " + loaded + "\n",
	})
	h.wants("Language and formats")
	if _, err := os.Stat(loaded); err == nil {
		t.Fatal("the answer was applied before it was given")
	}

	h.down().enter() // en
	got, err := os.ReadFile(loaded)
	if err != nil {
		t.Fatalf("the answer was never put in force: %v", err)
	}
	if strings.TrimSpace(string(got)) != "en" {
		t.Errorf("applied %q, want the answer that was just given", got)
	}
}

// A `first` question that is already answered is not asked again on the way in:
// a second start goes straight to the network, exactly as it would if nothing
// had ever been marked.
func TestAnAnsweredFirstQuestionIsNotAskedAgain(t *testing.T) {
	h := newHarness(t, map[string]string{
		treeFile: testInstaller +
			"  - name: LOCALE\n    title: Language and formats\n    required: true\n    first: true\n    default: de\n    values: [de, en]\n",
		"hooks/online.sh": "exit 1\n",
	})
	h.wants("There is no internet connection.").refuses("Language and formats")
}

// A question marked `blind` is asked before loadkeys has run, so even the key
// that would normally open the filter is typed on a layout nobody has chosen
// yet. Its box is up from the first frame, and typing narrows straight away —
// no / needed first.
func TestABlindQuestionOpensItsFilterFromTheStart(t *testing.T) {
	h := newHarness(t, map[string]string{
		treeFile: testInstaller +
			"  - name: KEYMAP\n    title: Console keyboard\n    required: true\n    first: true\n    blind: true\n    values: [us, de]\n",
	})
	h.wants("Console keyboard", "Filter …")
	h.typeIn("de")
	h.wants("de").refuses("us")
}

// ─── What this run is ────────────────────────────────────────────────────────

// A tree that can do more than one thing asks which before anything else
// follows from it — and what it asks with is entirely the tree's own words.
// What is chosen then decides which questions there are and what the run is
// called from there on.
const testModes = `
title: Test Installer
modes:
  - id: install
    title: Installation
    description: Put a system on this machine.
    confirm: Erasing {{DISK}}.
    stages: [go, finish]
  - id: repair
    title: Recovery
    description: Open a system already on a disk.
    confirm: Opening {{DISK}}.
    stages: [open]
variables:
  - name: DISK
    title: Disk
    required: true
    values: [/dev/sda]
  - name: SNAPSHOT
    title: Snapshot
    required: true
    values: [one, two]
    mode: repair
`

// modeFiles is that tree as the files it is made of: one task in each mode, and
// none of the standard ones.
var modeFiles = map[string]string{
	treeFile:                   testModes,
	"tasks/a-first/task.yaml":  "name: First\nstage: go\n",
	"tasks/b-second/task.yaml": "",
	"tasks/b-second/task.sh":   "",
	"tasks/c-extras/task.yaml": "",
	"tasks/c-extras/task.sh":   "",
	"tasks/d-open/task.yaml":   "name: Open the disk\nstage: open\n",
	"tasks/d-open/task.sh":     "echo opened\n",
}

func TestChoosingAModeSettlesTheQuestionsTheWarningAndTheRun(t *testing.T) {
	h := newHarness(t, modeFiles)
	h.wants("What to do", "Installation", "Recovery", "Put a system on this machine.")

	h.down().enter() // Recovery
	h.wants("Disk").enter()
	h.wants("Snapshot", "one", "two").enter()

	// The hub, the warning and the run are all read in the mode's own name, and
	// only its own stage runs.
	h.wants("Recovery", "Open a system already on a disk.").enter()
	h.wants("Ready to start", "Opening /dev/sda.", "Start Recovery").enter()
	h.ran()
	h.wants("Recovery complete in", "Open the disk")
	h.refuses("First")
}

func TestAQuestionGuardedByAModeIsNotAskedInTheOther(t *testing.T) {
	h := newHarness(t, modeFiles)
	h.enter() // Installation, the row the page opens on
	h.wants("Disk").enter()
	h.wants("Installation", "Put a system on this machine.")
	h.refuses("Snapshot")
	h.enter()
	h.wants("Erasing /dev/sda.", "Start Installation").enter()
	h.ran()
	h.wants("Installation complete in", "First")
	h.refuses("Open the disk")
}

// ─── Starting points ─────────────────────────────────────────────────────────

// A starting point is only a starting point once: a machine that has answered
// before is not asked again, because every value it filled in is by then an
// ordinary answer somebody may have changed.
func TestAPresetIsOnlyOfferedOnce(t *testing.T) {
	h := newHarness(t, nil)
	h.wants("Setup", "Full", "Bare")
	h.down().enter().typeIn("moritz").enter().enter()
	h.wants("Install", "Settings")

	h.restart()
	h.wants("Install", "Settings").refuses("Full", "Bare")
}

// A preset fills in answers, and an answer is an answer whether it was typed or
// chosen in one keypress. This tree ties its words on screen to one of them and
// puts the other into effect on the machine, which are the two things an answer
// can do beyond being stored.
func presetTreeTying(apply string) map[string]string {
	tree := strings.Replace(testInstaller,
		"          EXTRAS: \"true\"\n",
		"          EXTRAS: \"true\"\n          LOCALE: de_DE\n", 1)
	return map[string]string{
		treeFile: tree +
			"  - name: LOCALE\n    title: System language\n    required: true\n    values: [de_DE, en_US]\n" + apply +
			"language: LOCALE\n",
		"locales/de.yaml": "language: Deutsch\nmessages:\n  \"User name\": \"Benutzername\"\n",
	}
}

func TestAPresetCanChangeTheLanguageItIsReadIn(t *testing.T) {
	h := newHarness(t, presetTreeTying(""))
	h.enter() // Full, which fills in a German locale
	h.wants("Benutzername").refuses("User name")
}

func TestAPresetPutsWhatItFilledInInForce(t *testing.T) {
	loaded := filepath.Join(t.TempDir(), "loaded")
	h := newHarness(t, presetTreeTying("    apply: echo \"$LOCALE\" > "+loaded+"\n"))
	if _, err := os.Stat(loaded); err == nil {
		t.Fatal("a value was applied before the page that fills it in was answered")
	}

	h.enter() // Full
	got, err := os.ReadFile(loaded)
	if err != nil {
		t.Fatalf("what the preset filled in was never put in force: %v", err)
	}
	if strings.TrimSpace(string(got)) != "de_DE" {
		t.Errorf("applied %q, want the value the preset filled in", got)
	}
}

// ─── The language of the interface ───────────────────────────────────────────

// A tree that speaks more than one language but ties none of them to an answer
// of its own. The words on screen are then a setting of this program, and the
// tree's own language question is a question about the machine like any other.
func twoLanguageTree() map[string]string {
	return map[string]string{
		treeFile: testInstaller +
			"  - name: LOCALE\n    title: System language\n    required: true\n    values: [de_DE, en_US]\n",
		"locales/de.yaml": "language: Deutsch\nmessages:\n  \"Setup\": \"Einrichtung\"\n",
	}
}

// The language leads, because every word of every page after it is in it.
func TestTheInterfaceLanguageIsTheFirstThingAsked(t *testing.T) {
	h := newHarness(t, twoLanguageTree())
	h.wants("Interface language", "Deutsch").refuses("Full", "Bare")

	h.down().enter() // Deutsch
	h.wants("Einrichtung", "Full", "Bare")
}

// And it answers nothing about the machine being installed: the tree's own
// language question is still asked, and what was chosen here does not answer it.
func TestTheInterfaceLanguageIsNotAnAnswer(t *testing.T) {
	h := newHarness(t, twoLanguageTree())
	h.down().enter() // Deutsch
	if got := h.a.store.Get("LOCALE"); got != "" {
		t.Errorf("LOCALE = %q, want the interface language to have answered nothing", got)
	}

	h.down().enter()                   // Bare
	h.typeIn("moritz").enter().enter() // the user name, the disk
	h.wants("System language", "de_DE", "en_US")
}

// ─── The network ─────────────────────────────────────────────────────────────

// A tree with no internet problem to begin with never sees the network
// screen at all: it is a fix offered when one is needed, not a page every
// installation has to click through.
func TestNetworkScreenIsSkippedWhenAlreadyOnline(t *testing.T) {
	h := newHarness(t, map[string]string{
		"hooks/online.sh": "exit 0\n",
	})
	h.wants("Full", "Bare").refuses("Wireless network")
}

// Offline and nothing declared to join with: the screen says so and lets the
// installation carry on regardless — the tree's own preflight is what refuses
// properly if the connection still matters.
func TestNetworkScreenOffersToContinueWithoutWhenNotJoinable(t *testing.T) {
	h := newHarness(t, map[string]string{
		"hooks/online.sh": "exit 1\n",
	})
	h.wants("There is no internet connection.", "wireless network before continuing.")
	h.enter()
	h.wants("Full", "Bare")
}

// Offline with a full network description: the screen lists what is in range,
// joining one is what makes the check pass, and the installer moves on to its
// own opening exactly as it would have if there had been a cable plugged in.
func TestNetworkScreenJoinsAWirelessNetworkWhenOffline(t *testing.T) {
	marker := filepath.Join(t.TempDir(), "online")
	h := newHarness(t, map[string]string{
		"hooks/online.sh":        "test -e " + marker + "\n",
		"hooks/wlan-device.sh":   "printf wlan0\n",
		"hooks/wlan-networks.sh": "printf 'HomeNet\\nCafeNet\\n'\n",
		"hooks/wlan-connect.sh":  "touch " + marker + "\n",
	})
	h.wants("Wireless network", "HomeNet", "CafeNet")

	h.enter() // join HomeNet
	h.wants("HomeNet", "Passphrase")

	h.typeIn("secret").enter()
	h.wants("Full", "Bare") // online now, straight into the installer's own opening
}

// ─── The opening ─────────────────────────────────────────────────────────────

// One language on offer means no page asking about it: a question with one
// answer is not a question.
func TestOneLanguageIsNotAQuestion(t *testing.T) {
	newHarness(t, nil).wants("Full", "Bare").refuses("Language")
}

// A tree may tie the words on screen to one of its own answers — see
// `language:` in installer.yaml. Then where a machine is and which language it
// is spoken to in are one question, and the opening page of nothing but
// languages is not shown at all.
func TestATreeCanTieTheInterfaceToOneOfItsOwnAnswers(t *testing.T) {
	h := newHarness(t, regionTree)
	// "Deutsch" is the row the opening page of languages would have shown.
	h.wants("Language and region", "de_DE").refuses("Deutsch")

	// The answer is a locale rather than the name of a catalog, and it is read
	// as one: de_DE is German.
	h.enter()
	h.wants("Einrichtung")
	if got := h.a.store.Get(spec.LangVar); got != "de" {
		t.Errorf("%s = %q, want the language the answer came closest to", spec.LangVar, got)
	}
}

// And the other way: an answer no catalog fits leaves the language everything
// is written in standing.
func TestAnAnswerNoCatalogFitsLeavesTheSourceLanguage(t *testing.T) {
	h := newHarness(t, regionTree)
	h.down().enter()
	h.wants("Setup").refuses("Einrichtung")
}

// And the settings page does not offer a second way to set it: the tree's own
// row is the language, and a runtime row above it could only disagree with it.
func TestSettingsOffersNoLanguageOfItsOwnWhenTheTreeOwnsIt(t *testing.T) {
	h := newHarness(t, regionTree)
	h.down().enter() // en_US, so this page stays in the language it is read in
	h.down().enter().typeIn("moritz").enter().enter()
	h.down().enter() // Settings
	h.wants("Language and region", "en_US").refuses("Deutsch")
}

// The tree the two tests above are about: one question standing for a whole
// region, and a catalog for one of the languages it can come to.
var regionTree = map[string]string{
	treeFile: testInstaller +
		"  - name: LOCALE\n    title: Language and region\n    required: true\n    first: true\n" +
		"    values: [de_DE, en_US]\n" +
		"language: LOCALE\n",
	"locales/de.yaml": "language: Deutsch\nmessages:\n  \"Setup\": \"Einrichtung\"\n",
}

func TestTheOpeningRunsPresetThenQuestionsThenHub(t *testing.T) {
	h := newHarness(t, nil)
	h.wants("Full", "Everything at once.")

	// Bare, so the conditional question and the conditional stage stay away.
	h.down().enter()
	h.wants("User name", "The account you log in with.", "1 of 2")

	h.typeIn("moritz").enter()
	h.wants("Disk", "2 of 2", "/dev/sda  1TB")

	h.enter()
	h.wants("Install", "Settings")
}

// A preset is a set of answers and nothing more.
func TestAPresetFillsInAnswersAndStopsMattering(t *testing.T) {
	h := newHarness(t, nil)
	h.enter() // Full
	if got := h.a.store.Get("EXTRAS"); got != "true" {
		t.Fatalf("EXTRAS = %q", got)
	}
	// Extras being on opens a question that would not otherwise be asked.
	h.wants("1 of 3")
	h.typeIn("moritz").enter().enter()
	h.wants("Driver", "mesa", "nvidia")
}

// A run of questions is one place you stay in, not a path through the program.
func TestTheOpeningQuestionsShowACounterRatherThanATrail(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter().typeIn("moritz").enter()
	h.wants("2 of 2").refuses("User name ›")
}

// And the pages in front of that run are the same idea: they come one after
// another rather than one inside the other, so each is read under the heading
// of the opening instead of behind every page already answered.
func TestTheOpeningPagesStandUnderOneHeadingRatherThanInsideEachOther(t *testing.T) {
	h := newHarness(t, map[string]string{
		treeFile: testInstaller +
			"  - name: LOCALE\n    title: Language and formats\n    required: true\n    first: true\n    values: [de, en]\n" +
			"  - name: KEYMAP\n    title: Console keyboard\n    required: true\n    first: true\n    values: [de, us]\n",
	})
	h.wants("Start", "Language and formats")

	h.enter()
	h.wants("Start", "Console keyboard").refuses("Language and formats")

	h.enter()
	h.wants("Start", "Setup").refuses("Console keyboard")

	// And the run of questions leaves the opening behind it entirely.
	h.enter()
	h.wants("User name", "1 of 3").refuses("Setup")
}

func TestAnAnswerThatBreaksTheRulesIsRefusedWithTheReason(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter()
	h.typeIn("Moritz1").enter()
	h.wants("Lower case letters only.", "1 of 2")
	if got := h.a.store.Get("USER"); got != "" {
		t.Errorf("USER = %q, want the refused value not stored", got)
	}
}

func TestGoingBackReturnsToThePreviousQuestion(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter().typeIn("moritz").enter()
	h.wants("2 of 2")
	h.esc()
	h.wants("User name", "1 of 2")
}

// ─── Answers ─────────────────────────────────────────────────────────────────

// A tab in a command's output separates what is stored from what is read.
func TestADiskIsStoredByPathAndChosenBySize(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter().typeIn("moritz").enter()
	h.wants("/dev/sda  1TB", "/dev/sdb  2TB")
	h.down().enter()
	if got := h.a.store.Get("DISK"); got != "/dev/sdb" {
		t.Errorf("DISK = %q, want the path rather than the label", got)
	}
}

func TestEveryAnswerIsWrittenDownAsItIsGiven(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter().typeIn("moritz").enter()
	raw, err := os.ReadFile(h.a.store.Path())
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), "USER='moritz'") {
		t.Fatalf("the answer file does not hold the answer:\n%s", raw)
	}
}

// ─── Settings ────────────────────────────────────────────────────────────────

func TestSettingsShowsEveryAnswerOnOnePage(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter().typeIn("moritz").enter().enter()
	h.down().enter() // Settings
	h.wants("Identity", "User name", "moritz", "Storage", "Disk", "/dev/sda", "Extras", "No")
}

// A secret has no page behind it: it is not stored, so there is nothing here to
// change.
func TestSettingsSaysASecretIsAskedForLater(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter().typeIn("moritz").enter().enter()
	h.down().enter()
	h.wants("Password", "asked just before the run")
}

func TestChangingAValueInSettingsShowsTheNewOne(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter().typeIn("moritz").enter().enter()
	h.down().enter() // Settings
	h.enter()        // the first row, which is the first value
	h.wants("User name", "The account you log in with.")
	h.typeIn("x").enter()
	h.wants("moritzx")
}

// A page of answers narrows like any other long list, and keeps the heading the
// surviving rows sit under.
func TestSettingsNarrowsToTheAnswerBeingLookedFor(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter().typeIn("moritz").enter().enter()
	h.down().enter() // Settings
	h.typeIn("/disk")
	h.wants("Storage", "Disk", "/dev/sda").refuses("User name", "Identity")
}

// The heading counts as well as the name: a setting remembered as one of the
// storage ones is found by that.
func TestSettingsNarrowsByTheHeadingToo(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter().typeIn("moritz").enter().enter()
	h.down().enter()
	h.typeIn("/storage")
	h.wants("Storage", "Disk", "Extras").refuses("User name")
}

func TestSettingsSaysSoWhenNothingMatches(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter().typeIn("moritz").enter().enter()
	h.down().enter()
	h.typeIn("/zzz")
	h.wants("No matches").refuses("User name", "Disk")
}

// Narrowing is left before the page is: the first esc closes the box, the
// second goes back.
func TestEscClosesTheSettingsFilterBeforeItLeavesThePage(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter().typeIn("moritz").enter().enter()
	h.down().enter()
	h.typeIn("/disk").esc()
	h.wants("User name", "Disk")
	h.esc()
	h.wants("Install", "Settings")
}

// The query is how the row was found, so changing its value does not throw it
// away on the way back.
func TestTheSettingsFilterSurvivesChangingAValue(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter().typeIn("moritz").enter().enter()
	h.down().enter()
	h.typeIn("/disk").enter()
	h.down().enter() // the second disk
	h.wants("Disk", "/dev/sdb").refuses("User name")
}

// Turning a setting on can call for an answer nothing has asked for yet —
// extras on means a driver has to be chosen. Backing out of settings must run
// into that question rather than hand the hub a machine one enter key away
// from installing without it.
func TestTurningOnASettingAsksForWhatItNowRequiresOnTheWayOut(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter().typeIn("moritz").enter().enter()
	h.down().enter()            // Settings
	h.typeIn("/extras").enter() // the Extras row, currently No
	h.wants("Extras")
	h.key(tea.KeyUp).enter() // Yes is the row above No
	h.wants("Extras", "Yes")
	h.esc().esc() // close the filter, then leave settings
	h.wants("Driver", "mesa", "nvidia").refuses("Settings")
	h.enter() // mesa, the focused row
	h.wants("Install", "Settings")
}

// ─── Installing ──────────────────────────────────────────────────────────────

func TestTheConfirmationNamesTheDiskItIsAbout(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter().typeIn("moritz").enter().enter()
	h.enter() // Install
	h.wants("Ready to install", "Erasing /dev/sda.", "Start installation")
}

func TestTheSecretIsAskedForTwiceAndOnlyThenTheRunBegins(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter().typeIn("moritz").enter().enter()
	h.enter().enter() // Install, then start

	h.wants("Password")
	h.typeIn("hunter2").enter()
	h.wants("Repeat")
	h.typeIn("different").enter()
	h.wants("The entries do not match.", "Password")

	h.typeIn("hunter2").enter().typeIn("hunter2").enter()
	h.ran()
	h.wants("Installation complete", "First", "Second").refuses("Only with extras")
}

func TestAFailedTaskStopsTheRunAndSaysWhereItBroke(t *testing.T) {
	h := newHarness(t, map[string]string{
		"tasks/b-second/task.sh": "echo starting\nls /definitely/not/here\necho never\n",
	})
	h.down().enter().typeIn("moritz").enter().enter()
	h.enter().enter()
	h.typeIn("x").enter().typeIn("x").enter()
	h.ran()
	h.wants("Installation failed", "not/here", "Script", "Command", "Exit code")
}

// A task may ask before it runs, which is how a tree offers something
// rather than does it. Declining skips that one and the run carries on.
func TestAnTaskThatAsksIsOfferedRatherThanRun(t *testing.T) {
	h := newHarness(t, map[string]string{
		"tasks/d-reboot/task.yaml": "name: Reboot\nstage: finish\nconfirm: Restart {{DISK}} now?\n",
		"tasks/d-reboot/task.sh":   "echo never\n",
	})
	h.down().enter().typeIn("moritz").enter().enter()
	h.enter().enter()
	h.typeIn("x").enter().typeIn("x").enter()

	h.asked()
	h.wants("Reboot", "Restart /dev/sda now?", "Yes", "No")

	// No: the row keeps its place in the list, marked as passed over.
	h.down().enter()
	h.ran()
	h.wants("Installation complete", "First", "Second", "Reboot")
}

// An offer opens on yes unless the task says otherwise, and one that says `no`
// is answered no by an enter nobody aimed at it — which is the whole point:
// the run is over, and the offer under it is an extra.
func TestAnOfferCanOpenOnNo(t *testing.T) {
	h := newHarness(t, map[string]string{
		"tasks/d-shell/task.yaml": "name: Shell\nstage: finish\nconfirm: Open a shell?\ndefault: no\n",
		// Would fail the run if it were ever started.
		"tasks/d-shell/task.sh": "exit 1\n",
	})
	h.down().enter().typeIn("moritz").enter().enter()
	h.enter().enter()
	h.typeIn("x").enter().typeIn("x").enter()

	h.asked()
	h.wants("Shell", "Open a shell?", "Yes", "No")

	h.enter()
	h.ran()
	h.wants("Installation complete", "Shell")
}

// A value that could not have been known before the work started: the run
// stops where the list of tasks was, asks, and carries on with the answer — and
// the offer after it can name what was just chosen.
func TestATaskCanAskForAValueInTheMiddleOfTheRun(t *testing.T) {
	h := newHarness(t, map[string]string{
		treeFile: testInstaller + `
  - name: SNAPSHOT
    title: Snapshot
    description: Which one to go back to.
    required: true
    command: printf 'one\ntwo\n'
`,
		"tasks/d-roll/task.yaml": "name: Roll back\nstage: finish\nasks: SNAPSHOT\nconfirm: Replace @ with {{SNAPSHOT}}?\n",
		"tasks/d-roll/task.sh":   "echo rolled\n",
	})
	h.down().enter().typeIn("moritz").enter().enter()
	h.enter().enter()
	h.typeIn("x").enter().typeIn("x").enter()

	h.askedFor()
	h.wants("Roll back", "Which one to go back to.", "one", "two")

	// The answer is stored, and the offer that follows reads it back.
	h.down().enter()
	h.asked()
	h.wants("Replace @ with two?")
	if got := h.a.store.Get("SNAPSHOT"); got != "two" {
		t.Errorf("SNAPSHOT = %q, want two", got)
	}

	h.enter()
	h.ran()
	h.wants("Installation complete", "Roll back")
}

// A question the run stopped for that turns out to have no answers is the end
// of the run: the work has happened, and what it was waiting for is not here.
func TestAskingForSomethingThatIsNotThereEndsTheRun(t *testing.T) {
	h := newHarness(t, map[string]string{
		treeFile: testInstaller + `
  - name: SNAPSHOT
    title: Snapshot
    command: "true"
`,
		"tasks/d-roll/task.yaml": "name: Roll back\nstage: finish\nasks: SNAPSHOT\n",
		"tasks/d-roll/task.sh":   "echo never\n",
	})
	h.down().enter().typeIn("moritz").enter().enter()
	h.enter().enter()
	h.typeIn("x").enter().typeIn("x").enter()
	h.ran()
	h.wants("Installation failed", "there is nothing to choose from")
}

// Nothing typed while a run is going may dismiss its result, and nothing said
// in confidence survives it.
func TestASecretIsForgottenWhenTheRunIsOver(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter().typeIn("moritz").enter().enter()
	h.enter().enter()
	h.typeIn("hunter2").enter().typeIn("hunter2").enter()
	h.ran()
	if got := h.a.store.Get("PW"); got != "" {
		t.Errorf("PW = %q after the run", got)
	}
}

// ─── The system check ────────────────────────────────────────────────────────

func TestAFailedSystemCheckIsAWall(t *testing.T) {
	h := newHarness(t, map[string]string{
		"hooks/preflight.sh": "echo Set the boot mode to UEFI. >&2\nexit 1\n",
	})
	h.wants("Cannot continue", "Set the boot mode to UEFI.")
	// Nothing leads anywhere from here: the only key that does anything leaves.
	h.esc()
	if !h.m.quitting {
		t.Error("esc on the wall did not leave")
	}
}

func TestASystemCheckThatPassesLeadsStraightOn(t *testing.T) {
	h := newHarness(t, map[string]string{
		"hooks/preflight.sh": "echo fine\n",
	})
	h.wants("Full", "Bare")
}

// Nothing this program draws may run past the edge of the terminal, at any size
// a terminal comes in. 80x24 is the smallest one is guaranteed to be.
func TestNoPageEverRunsPastTheEdge(t *testing.T) {
	sizes := [][2]int{{80, 24}, {100, 30}, {200, 60}, {34, 13}}
	pages := []func(*harness){
		func(h *harness) {},                                                                   // the preset page
		func(h *harness) { h.down().enter() },                                                 // the first question
		func(h *harness) { h.down().enter().typeIn("moritz").enter() },                        // a list of answers
		func(h *harness) { h.down().enter().typeIn("moritz").enter().enter() },                // the hub
		func(h *harness) { h.down().enter().typeIn("moritz").enter().enter().down().enter() }, // settings
		func(h *harness) { h.down().enter().typeIn("moritz").enter().enter().enter() },        // the confirmation
		func(h *harness) { h.down().enter().typeIn("moritz").enter().enter().typeIn("q") },    // the way out
	}
	for _, open := range pages {
		h := newHarness(t, leaveTree("true", "true"))
		open(h)
		for _, size := range sizes {
			h.send(tea.WindowSizeMsg{Width: size[0], Height: size[1]})
			for _, line := range strings.Split(h.screen(), "\n") {
				if w := lipgloss.Width(line); w > size[0] {
					t.Fatalf("at %dx%d a line is %d wide:\n%s", size[0], size[1], w, line)
				}
			}
		}
	}
}

// A failure report is the one page that has to be readable on the narrowest
// terminal there is: it is what somebody photographs and sends to a forum.
func TestAFailureReportFitsTheSmallestTerminal(t *testing.T) {
	h := newHarness(t, map[string]string{
		"tasks/a-first/task.sh": "echo starting\nls /definitely/not/here\necho never\n",
	})
	h.down().enter().typeIn("moritz").enter().enter()
	h.enter().enter().typeIn("x").enter().typeIn("x").enter()
	h.ran()
	h.send(tea.WindowSizeMsg{Width: 80, Height: 24})
	view := h.screen()
	for _, want := range []string{"Installation failed", "Script", "Command", "Exit code"} {
		if !strings.Contains(view, want) {
			t.Errorf("the report is missing %q at 80x24:\n%s", want, view)
		}
	}
}

// The smallest tree that is still an installer: some questions and something to
// do. Everything else the runtime offers — a language to pick, a starting
// point, a task that asks first — is a page that simply does not appear.
func TestTheSmallestTreeStillWorks(t *testing.T) {
	h := newHarness(t, map[string]string{
		treeFile:                   "title: Test Installer\nstages: [go]\nvariables:\n  - name: USER\n    title: User name\n    required: true\n",
		"tasks/a-first/task.yaml":  "name: Do it\nstage: go\n",
		"tasks/b-second/task.yaml": "",
		"tasks/b-second/task.sh":   "",
		"tasks/c-extras/task.yaml": "",
		"tasks/c-extras/task.sh":   "",
	})
	// Straight to the one question: no preset page, because there are no presets.
	h.wants("User name", "1 of 1")
	h.typeIn("moritz").enter()
	h.wants("Install", "Settings")

	// No confirmation sentence to show, and no secret to ask for.
	h.enter().wants("Ready to install", "Start installation")
	h.enter().ran()
	h.wants("Installation complete", "Do it")

	// Nothing follows a finished installation: enter on the result leaves.
	h.enter()
	if !h.m.quitting {
		t.Error("enter on a finished installation did not leave")
	}
}

// ─── Leaving ─────────────────────────────────────────────────────────────────

// A tree that says how this machine is put down is a tree saying the installer
// cannot simply be quit: the machine booted to run it and there is nothing
// behind it to quit into.
func leaveTree(restart, shutdown string) map[string]string {
	return map[string]string{
		"hooks/restart.sh":  restart + "\n",
		"hooks/shutdown.sh": shutdown + "\n",
	}
}

func TestQuittingAsksWhatToDoWithTheMachine(t *testing.T) {
	h := newHarness(t, leaveTree("true", "true"))
	h.down().enter().typeIn("moritz").enter().enter()
	h.wants("Install", "Settings")

	h.typeIn("q")
	h.wants("Restart", "Shut down").refuses("Exit to the console")
	if h.m.quitting {
		t.Fatal("q left the program instead of asking")
	}

	// And it is a question like any other: esc is the way back to the hub.
	h.esc()
	h.wants("Install", "Settings")
}

// Where the tree says there is a console behind the installer, there is a third
// way out: the program stops and the machine keeps running. What it leaves on
// the terminal is the tree's own sentence, because a bare prompt says nothing
// about how to get back.
func TestLeavingToTheConsoleClosesOnlyTheProgram(t *testing.T) {
	const back = "Type installer to start it again."
	files := leaveTree("true", "true")
	files[treeFile] = testInstaller + "console: " + back + "\n"

	h := newHarness(t, files)
	h.down().enter().typeIn("moritz").enter().enter()
	h.typeIn("q")
	h.wants("Restart", "Shut down", "Exit to the console")

	// The sentence belongs to the row, so it is under the list once the cursor
	// is on it.
	h.down().down()
	h.wants(back)

	h.enter()
	if !h.m.quitting {
		t.Fatal("choosing the console did not leave the program")
	}
	if h.a.farewell != back {
		t.Errorf("farewell = %q, want the sentence the tree wrote", h.a.farewell)
	}
}

func TestChoosingRestartRunsTheTreesOwnCommand(t *testing.T) {
	marker := filepath.Join(t.TempDir(), "restarted")
	h := newHarness(t, leaveTree("touch "+marker, "true"))
	h.down().enter().typeIn("moritz").enter().enter()
	h.typeIn("q").enter()

	if _, err := os.Stat(marker); err != nil {
		t.Fatalf("the machine was never restarted: %v", err)
	}
	if !h.m.quitting {
		t.Error("the interface stayed up after the machine was put down")
	}
}

// A command that does not work leaves the machine running, so the page has to
// stay standing and say so rather than closing into a terminal nobody is
// looking at.
func TestAMachineThatWillNotRestartIsSaidSo(t *testing.T) {
	h := newHarness(t, leaveTree("exit 1", "true"))
	h.down().enter().typeIn("moritz").enter().enter()
	h.typeIn("q").enter()

	if h.m.quitting {
		t.Fatal("the interface left although the machine is still running")
	}
	h.wants("did not do as it was told", "Restart", "Shut down")
}

// Nothing follows a finished installation but the machine being put down.
func TestAFinishedInstallationEndsOnTheWayOut(t *testing.T) {
	h := newHarness(t, leaveTree("true", "true"))
	h.down().enter().typeIn("moritz").enter().enter()
	h.enter().enter()
	h.typeIn("x").enter().typeIn("x").enter()
	h.ran()
	h.wants("Installation complete")

	h.enter()
	h.wants("Restart", "Shut down")
	if h.m.quitting {
		t.Error("a finished installation left rather than asking")
	}
}

// ctrl+c during a run is the one way out of one, and it has to be meant. What
// it stops is over: the page it leads to has nothing behind it, so esc there is
// not a way back into an installation that is no longer running.
func TestCtrlCDuringARunStopsItAndOffersNoWayBack(t *testing.T) {
	files := leaveTree("true", "true")
	files["tasks/a-first/task.sh"] = "sleep 30\n"
	h := newHarness(t, files)
	h.down().enter().typeIn("moritz").enter().enter()
	h.enter().enter()
	h.typeIn("x").enter().typeIn("x").enter()
	h.wants("Installing for")

	h.ctrlC()
	h.wants("Restart", "Shut down")
	h.esc()
	h.wants("Restart", "Shut down")
	if h.m.quitting {
		t.Error("esc on the way out left the program")
	}
}

// The clock is the whole point of the headline: an installation is minutes of a
// list filling in, and how long it has been going is the one thing nobody
// watching can work out for themselves.
func TestTheHeadlineCarriesTheClock(t *testing.T) {
	h := newHarness(t, nil)
	h.down().enter().typeIn("moritz").enter().enter()
	h.enter().enter()
	h.typeIn("x").enter().typeIn("x").enter()
	h.ran()
	h.wants("Installation complete in 00:0")
}

func TestClockReadsAsAClock(t *testing.T) {
	cases := []struct {
		d    time.Duration
		want string
	}{
		{0, "00:00"},
		{9 * time.Second, "00:09"},
		{8*time.Minute + 21*time.Second, "08:21"},
		{59*time.Minute + 59*time.Second, "59:59"},
		{time.Hour + 5*time.Minute + 3*time.Second, "1:05:03"},
		{-time.Second, "00:00"},
	}
	for _, c := range cases {
		if got := clock(c.d); got != c.want {
			t.Errorf("clock(%s) = %q, want %q", c.d, got, c.want)
		}
	}
}

// ─── What a run has to report ────────────────────────────────────────────────

// A run of two dozen identical-looking rows cannot say that the work is done
// and everything after it is an offer. So a task may stop the run and say it,
// once, on a page of its own — with whatever it produced drawn as a code for
// the machine in somebody's hand.
func TestATaskCanReportWhatItProduced(t *testing.T) {
	h := newHarness(t, map[string]string{
		treeFile: testInstaller + `
  - name: LINK
    title: Shared at
`,
		"tasks/d-share/task.yaml": "name: Share\nstage: finish\nshows: LINK\nreport: |\n  Installed on {{DISK}}\n\n  Everything after this is offered rather than needed.\n",
		// A script answers by writing one line of the answer file, which is the
		// only channel there is and the same one a person editing it uses.
		"tasks/d-share/task.sh": `printf "LINK='https://example.test/abc'\n" >>"$INSTALLER_CONF"` + "\n",
	})
	h.down().enter().typeIn("moritz").enter().enter()
	h.enter().enter()
	h.typeIn("x").enter().typeIn("x").enter()

	h.reported()
	// The words are the tree's, filled in from the answers, and the value the
	// task wrote is on the page as itself.
	h.wants("Installed on /dev/sda", "Everything after this is offered", "https://example.test/abc")
	// A page being read is not a run in progress: no counter, no turning mark.
	h.refuses("of 3")

	// And it is an answer like any other from here on.
	if got := h.a.store.Get("LINK"); got != "https://example.test/abc" {
		t.Errorf("LINK = %q, want the address the task wrote", got)
	}

	h.enter()
	h.ran()
	h.wants("Installation complete", "Share")
}

// A task that produced nothing still says what it has to say. Not being able to
// share a configuration is not a reason to withhold the news that the machine
// is installed.
func TestAReportWithNothingToShowIsStillShown(t *testing.T) {
	h := newHarness(t, map[string]string{
		treeFile: testInstaller + `
  - name: LINK
    title: Shared at
`,
		"tasks/d-share/task.yaml": "name: Share\nstage: finish\nshows: LINK\nreport: Installed on {{DISK}}\n",
		"tasks/d-share/task.sh":   "echo 'it did not work' >&2\n",
	})
	h.down().enter().typeIn("moritz").enter().enter()
	h.enter().enter()
	h.typeIn("x").enter().typeIn("x").enter()

	h.reported()
	h.wants("Installed on /dev/sda")
}

// ─── A starting point that is fetched rather than written down ───────────────

// The third kind of starting point: not a set of answers in the tree but a code
// somebody was handed, and the answers behind it. One row, one question, and
// from the next page on nothing about it is any different.
func TestAPresetCanFetchItsAnswers(t *testing.T) {
	h := newHarness(t, presetFetches("printf \"USER='moritz'\\nDISK='/dev/sdb'\\nEXTRAS='false'\\n\" >>\"$INSTALLER_CONF\""))
	h.down().down()
	h.wants("Online")

	// An answer has already been written down once, which is what a real run
	// looks like by the time it reaches this page — so the file carries an empty
	// line for the code, and reading it back would undo the answer about to be
	// given unless that answer is written down first.
	if err := h.a.store.Save(); err != nil {
		t.Fatal(err)
	}

	h.enter()
	h.wants("Configuration code")
	h.typeIn("abc12").enter().answered()

	// Everything the code stood for is an answer now, and with nothing left
	// open the hub is what follows.
	h.wants("Install", "Settings")
	for name, want := range map[string]string{"USER": "moritz", "DISK": "/dev/sdb", "EXTRAS": "false"} {
		if got := h.a.store.Get(name); got != want {
			t.Errorf("%s = %q, want %q", name, got, want)
		}
	}
	if got := h.a.store.Get("SOURCE"); got != "abc12" {
		t.Errorf("SOURCE = %q, want abc12", got)
	}
}

// A code that stands for nothing is a page that has not moved, with the reason
// on it in the shell's own words — there is nothing to do about it but read
// that and try another.
func TestAPresetThatCannotFetchSaysWhyAndStaysPut(t *testing.T) {
	h := newHarness(t, presetFetches("echo 'Nothing is shared under that code' >&2; exit 1"))
	h.down().down().enter()
	h.typeIn("nope").enter().answered()

	h.wants("Configuration code", "Nothing is shared under that code")
	h.refuses("Settings")
	if _, ok := h.m.top().(*fieldScreen); !ok {
		t.Errorf("the page moved on to %T", h.m.top())
	}
}

// presetFetches is the test tree with a third starting point on it: one that
// asks for a code and runs the given shell to make something of it.
func presetFetches(apply string) map[string]string {
	tree := strings.Replace(testInstaller, "\nvariables:", `
      - id: shared
        title: Online
        description: Take the answers from somewhere else.
        asks: SOURCE
        apply: `+apply+`
variables:`, 1)
	return map[string]string{treeFile: tree + `
  - name: SOURCE
    title: Configuration code
    description: The code of a configuration somebody shared.
    required: true
`}
}

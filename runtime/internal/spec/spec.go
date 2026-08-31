// Package spec is the installer tree, read into memory: what the installer is
// called, what it needs to know, and what it does.
//
// A tree is one installer.yaml and the folders beside it. Everything in it is
// data. The runtime ships no tree of its own — without one there is no
// installer, only a binary that says so and stops. That is the whole point of
// the split: this package knows the shape of the yaml, and nothing in the
// program below it knows a single thing about the system being installed.
package spec

import (
	"regexp"
	"slices"
	"strings"

	"installer/internal/i18n"
)

// What a tree is made of. Only installer.yaml has to be there; everything else
// is found by its own name, so a tree turns a part of the program off by
// leaving the file or folder out rather than by declaring anything.
const (
	FileInstaller = "installer.yaml" // what the installer is, asks, and does
	FileLib       = "lib.sh"         // shell put in front of every script
	DirTasks      = "tasks"          // the installation, one folder per step
	DirHooks      = "hooks"          // everything around it, one script per hook
	DirLocales    = "locales"        // one catalog per language the tree speaks
	FileTask      = "task.yaml"      // where a step belongs
	FileScript    = "task.sh"        // what it does
	ScriptExt     = ".sh"
)

// The hooks, each a bash script in hooks/ called by its own name. This is
// everything the runtime does around the installation: nothing here installs
// anything, and a tree that leaves one out simply does not get that part.
const (
	HookPreflight = "preflight"     // can this machine be installed onto at all
	HookOnline    = "online"        // is there internet
	HookDevice    = "wlan-device"   // the wireless device to use
	HookNetworks  = "wlan-networks" // the networks in range, one per line
	HookConnect   = "wlan-connect"  // join one
	HookRestart   = "restart"       // put this machine down and start it again
	HookShutdown  = "shutdown"      // switch it off
)

// HookNames is every hook there is. A file in hooks/ that is not one of them is
// refused when the tree loads, the way a misspelled yaml key is: a hook that is
// never called because its name has a typo in it is the worst kind of
// authoring bug, since everything loads and nothing happens.
var HookNames = []string{
	HookPreflight, HookOnline, HookDevice, HookNetworks, HookConnect,
	HookRestart, HookShutdown,
}

// The runtime's own settings: the two keys it writes into the answer file that
// no installer.yaml declared. Neither is something an installer's data can own —
// the words the interface is read in belong to the frame, and which of the
// tree's modes is being carried out is a decision about the program rather than
// a value inside it.
//
// A tree may not declare either, and may name either in a `conditions:` — which
// is how a variable says it only belongs to one of the modes.
const (
	LangVar = "INSTALLER_LANG"
	ModeVar = "INSTALLER_MODE"
)

// RuntimeVars is every name that belongs to the runtime rather than to a tree.
var RuntimeVars = []string{LangVar, ModeVar}

// runtimeVar reports whether a name is one of them.
func runtimeVar(name string) bool { return slices.Contains(RuntimeVars, name) }

// Spec is a whole installer tree.
type Spec struct {
	Dir string // absolute, and never written to

	UI      UI
	Presets []*Preset
	Vars    []*Variable

	// Modes are the things this tree can do, in the order it offers them. There
	// is always at least one: a tree that declares none has exactly one made of
	// its own top-level stages and confirm, and is never asked which.
	Modes []*Mode

	// Stages are the phases the work happens in, in the order they happen —
	// every mode's own, one after another. Every task names one, which is what
	// puts it in a run, where, and in which mode.
	Stages []string

	// Tasks, already in the order they run: by stage, and inside a stage by what
	// they declared they need. Sorted once when the tree is loaded, so there is
	// one order and everything downstream reads it rather than works it out
	// again.
	Tasks []*Task

	// Lib is the shell every script of this tree is given before its own, and
	// Locales the folder its catalogs live in. Both are whatever FileLib and
	// DirLocales turned out to be, or empty where the tree has neither.
	Lib     string
	Locales string

	// Language names the variable whose answer also settles the words this
	// interface is read in — a tree that asks where a machine is has asked which
	// language it speaks, and asking again would be the same question twice. The
	// answer is matched against the catalogs on offer the way a machine's own
	// locale is, so de_AT is German without anything having to say so.
	//
	// Empty leaves the two apart, and the program asks for a language of its own
	// on the way in.
	Language string

	hooks  map[string]string
	byName map[string]*Variable
}

// UI is what the tree says about itself: the words and the one colour that make
// the frame this installer rather than any other.
type UI struct {
	Title  string `yaml:"title"`
	Logo   string `yaml:"logo"`
	Accent string `yaml:"accent"`

	// Console is the sentence read on the way out of the interface, where the
	// machine keeps running. What the installer is called out there is something
	// only the tree can know, and somebody who has just left it is looking at a
	// bare prompt. Empty leaves that row off, which is right for an image where
	// there is nothing behind the interface.
	Console string `yaml:"console"`
}

// Mode is one of the things a tree can do: a run with a name, a warning of its
// own, and the phases it happens in.
//
// An installer that can also repair what it installed is not one program with a
// switch in it — the two ask different questions, do different work and are
// dangerous in different ways. So a tree says what it can do rather than what it
// is, and the program asks which of them this run is before anything else
// happens. A tree with one mode is never asked and never notices.
//
// Nothing about a mode reaches a task. A task names a stage, as it always did,
// and the stage says which mode it belongs to — so the two can never disagree
// and no unit has to repeat what its stage already said.
type Mode struct {
	ID          string `yaml:"id"`
	Title       string `yaml:"title"`
	Description string `yaml:"description"`

	// Confirm is the last thing read before this mode's first task runs, with
	// {{VAR}} filled in from the answers — the sentence that says which disk is
	// about to be erased.
	Confirm string `yaml:"confirm"`

	// Stages are this mode's phases, in the order they happen. They are its own:
	// no two modes may name the same one, since a stage is what a task points at
	// to say where it belongs.
	Stages []string `yaml:"stages"`
}

func (m *Mode) Label() string { return i18n.T(m.Title) }
func (m *Mode) Help() string  { return i18n.T(m.Description) }

// ConfirmText is the last sentence before this mode's first task, translated
// and with {{VAR}} filled in from the answers.
func (m *Mode) ConfirmText(get func(string) string) string {
	return strings.TrimSpace(Expand(i18n.T(m.Confirm), get))
}

// Mode finds a mode by id, or nil where the tree has no such one.
func (s *Spec) Mode(id string) *Mode {
	for _, m := range s.Modes {
		if m.ID == id {
			return m
		}
	}
	return nil
}

// Asked reports whether which mode this run is in is a question at all. One
// mode is not a choice, and a page offering it would be a page with a single
// row on it.
func (s *Spec) Asked() bool { return len(s.Modes) > 1 }

// Hook is the script this tree put in hooks/ under that name, absolute, or
// empty where it has none.
func (s *Spec) Hook(name string) string { return s.hooks[name] }

// Source is the shell that runs a script file, for the places that take shell
// rather than a path. Empty in, empty out — a hook a tree does not have.
func Source(path string) string {
	if path == "" {
		return ""
	}
	return "source " + quote(path)
}

// Leaves reports whether this machine can be left at all: a tree that says how
// is saying the machine booted to run the installer, so every way out of the
// interface asks what to do with it instead of quitting.
func (s *Spec) Leaves() bool {
	return s.Hook(HookRestart) != "" || s.Hook(HookShutdown) != "" || s.UI.Console != ""
}

// ConsoleHelp is the sentence under the row that leaves the machine running:
// what to type to be back here.
func (s *Spec) ConsoleHelp() string { return i18n.T(s.UI.Console) }

// Preset is one page of starting points: a question a machine with no answer
// file is asked before the real ones, answered by choosing one of the options
// under it. It is the only place a value arrives without being typed.
//
// A tree may declare several, and each is a page of its own, asked in the order
// they are declared.
type Preset struct {
	ID          string          `yaml:"id"`
	Title       string          `yaml:"title"`
	Description string          `yaml:"description"`
	Options     []*PresetOption `yaml:"options"`

	// Mode is the mode this page belongs to, empty for all of them. A set of
	// starting points for an installation is not a question to put to somebody
	// who came here to repair one.
	Mode string `yaml:"mode"`
}

// Applies reports whether this page of starting points is worth offering.
func (p *Preset) Applies(get func(string) string) bool { return inMode(p.Mode, get) }

// PresetOption is one answer to that question: the values choosing it fills in.
// Nothing else about it survives being chosen — it is a set of answers, not a
// mode the installer stays in.
type PresetOption struct {
	ID          string            `yaml:"id"`
	Title       string            `yaml:"title"`
	Description string            `yaml:"description"`
	Values      map[string]Scalar `yaml:"values"`
}

func (p *Preset) Label() string { return i18n.T(p.Title) }
func (p *Preset) Help() string  { return i18n.T(p.Description) }

func (o *PresetOption) Label() string { return i18n.T(o.Title) }
func (o *PresetOption) Help() string  { return i18n.T(o.Description) }

// Task is one unit of work: a folder holding what it is, and the script that
// does it.
//
// It says where it belongs rather than when it runs — a stage, and what it
// needs from its own stage — and the order follows from that. Nothing keeps a
// list of the installation's steps: adding a folder adds a step, and the two
// can never disagree.
type Task struct {
	Name       string     `yaml:"name"`
	Stage      string     `yaml:"stage"`
	Needs      []string   `yaml:"needs"`
	Conditions Conditions `yaml:"conditions"`

	// Asks names a variable whose answer is not knowable before this point: the
	// snapshot to go back to, once the disk holding it is open. The run stops and
	// puts the question in the frame, exactly where the list of tasks was, and
	// carries on with the answer.
	//
	// It is asked every time, whatever the answer file says. A value that had to
	// wait for the work to start is a value about what the work found, and last
	// run found something else.
	Asks string `yaml:"asks"`

	// Confirm is asked before this one runs, as a yes or no in the frame.
	// Declining skips it and the run carries on — which is what makes an
	// offer ("reboot now?") a unit like any other rather than a page of its own.
	// It comes after `asks`, so the offer can name what was just chosen.
	Confirm string `yaml:"confirm"`

	// Default is which of the two answers the offer opens on: `yes`, which is
	// what it is when nothing says otherwise, or `no`.
	//
	// Most offers are the obvious next thing and belong on yes. The ones that
	// are an extra — a root shell inside the system that was just installed —
	// belong on no, so that an enter meant for the page before it does not walk
	// into one.
	Default Scalar `yaml:"default"`

	// Quits marks a task the program does not come back from — a reboot. The
	// frame stops drawing rather than waiting for output nobody will read.
	Quits bool `yaml:"quits"`

	// TTY hands this one the terminal: it draws over the interface, keyboard
	// and all, and the frame comes back untouched when it exits. For the one
	// kind of unit that is a session rather than a step — a shell in the system
	// that was just installed.
	TTY bool `yaml:"tty"`

	id   string
	mode string
	path string
	cond []*condition
}

func (t *Task) Label() string { return i18n.T(t.Name) }

// Mode is the mode this task belongs to, which is whichever one owns its stage.
func (t *Task) Mode() string { return t.mode }

// ID is the folder this task was read from, which is also the name other tasks
// reach it by in their needs.
func (t *Task) ID() string { return t.id }

// Path is the script it runs, absolute.
func (t *Task) Path() string { return t.path }

// Confirms reports whether this one is offered rather than simply run.
func (t *Task) Confirms() bool { return t.Confirm != "" }

// Declines reports whether the offer opens on no rather than on yes.
func (t *Task) Declines() bool { return t.Default == ConfirmNo }

// The two answers `default:` takes on a task. They are the words somebody
// writing a task.yaml would reach for, not the true/false a variable is stored
// as: this is which row a question opens on, not a value anything reads back.
const (
	ConfirmYes = "yes"
	ConfirmNo  = "no"
)

// Question is the offer, translated and with the answers filled in.
func (t *Task) Question(get func(string) string) string {
	return strings.TrimSpace(Expand(i18n.T(t.Confirm), get))
}

// The shapes a variable takes. The type is what the frame draws; a set of
// values or a command turns the default text box into a list without anything
// having to say so.
const (
	TypeText   = "text"
	TypeBool   = "bool"
	TypeSecret = "secret"
)

// The two answers a bool variable has. They are written into the answer file
// and read by scripts as plain shell truth, so they are these words and not
// yes/no — a script tests `[ "$X" = true ]`.
const (
	BoolTrue  = "true"
	BoolFalse = "false"
)

// Variable is one thing the installer needs to know, and everything known
// about what a valid answer looks like. The rules live here once and are used
// both when asking and when reading back an answer file somebody edited by
// hand — a value typed into the file never passed a prompt.
type Variable struct {
	Name        string `yaml:"name"`
	Title       string `yaml:"title"`
	Description string `yaml:"description"`

	// Group is the heading this row sits under on the settings page. Rows keep
	// the order they were declared in, so a group is simply the run of rows
	// that named it — there is nothing to declare up front.
	Group string `yaml:"group"`

	// Mode is the mode this question belongs to, empty for all of them.
	//
	// It is how a tree that does more than one thing keeps its questions apart,
	// and it is a key of its own rather than a condition because there is
	// nothing to compare: a question is one mode's or it is everybody's. The
	// few that are everybody's are the ones asked before the mode is — the
	// keyboard both sides are typed on.
	Mode string `yaml:"mode"`

	Type     string `yaml:"type"`
	Default  Scalar `yaml:"default"`
	Required bool   `yaml:"required"`

	// First puts this question before everything else the program does — before
	// the network screen, before the tree's own check of the machine, before the
	// starting point is chosen. For the answer that everything after it is typed
	// on: a wireless passphrase given on a keyboard nobody chose is not the
	// passphrase, and there is nothing to be done about that afterwards.
	//
	// It is a promise a tree should make sparingly. Every question here is a
	// question asked before the check that says this machine cannot be installed
	// onto at all.
	First bool `yaml:"first"`

	// Blind marks the one first question whose own answer is what loadkeys is
	// about to run. Until it is answered, no key on this machine is known to
	// print what it looks like it does — not even the / that would otherwise
	// open the box narrowing its list. So that box is shown from the first
	// frame instead of waited for, and does not close: a box nobody can find
	// the key to open is no box at all.
	Blind bool `yaml:"blind"`

	// Where the answers come from, when there is a set of them: written out, or
	// printed by a command one per line. A variable with neither is free text.
	Values  []string `yaml:"values"`
	Command string   `yaml:"command"`

	// Free is the row that opens a text box under a list of answers, for the
	// variable whose list is a suggestion rather than the whole set. Its text is
	// the row's own label; empty offers no such row, which is what a closed set
	// wants.
	Free string `yaml:"free"`

	// Prefill prints a suggested answer — a timezone guessed from the network,
	// a keymap read off the live system. Only ever a suggestion: it fills the
	// box, it does not answer the question.
	Prefill string `yaml:"prefill"`

	// Apply puts this answer into effect on the machine the installer is running
	// on, rather than on the one being installed. Almost nothing needs it — an
	// answer is a string a script reads later — but a console keyboard is not a
	// string: until it is loaded, every answer after it is typed on a layout
	// nobody chose. It runs when the answer is given, and once at startup for an
	// answer this run began with.
	Apply string `yaml:"apply"`

	Pattern    string     `yaml:"pattern"`
	Error      string     `yaml:"error"`
	Conditions Conditions `yaml:"conditions"`

	re       *regexp.Regexp
	cond     []*condition
	deferred bool
}

// Deferred reports whether this value is one a task asks for in the middle of a
// run — see Task.Asks. Nothing declares it: being named by a task is the
// declaration.
//
// It is the second kind of required value that does not stop the program from
// being ready, and for the same reason a secret is the first: there is no
// answering it yet. A snapshot to go back to cannot be chosen, or shown on a
// settings page, while the disk holding it is still locked.
func (v *Variable) Deferred() bool { return v.deferred }

func (v *Variable) Label() string { return i18n.T(v.Title) }
func (v *Variable) Help() string  { return i18n.T(v.Description) }

// FreeLabel is the row that opens a text box under a list of answers.
func (v *Variable) FreeLabel() string { return i18n.T(v.Free) }
func (v *Variable) GroupLabel() string {
	if v.Group == "" {
		return ""
	}
	return i18n.T(v.Group)
}

// Why is what to say about an answer that will not do. A variable that declares
// nothing gets a sentence naming the rule it broke, so a tree is never obliged
// to write one out for every field.
func (v *Variable) Why() string {
	if v.Error != "" {
		return i18n.T(v.Error)
	}
	if v.Pattern != "" {
		return i18n.T("This value has the wrong format.")
	}
	return i18n.T("This value is required.")
}

// Shape is the type with the empty default filled in, so everything else can
// switch on exactly three values.
func (v *Variable) Shape() string {
	if v.Type == "" {
		return TypeText
	}
	return v.Type
}

// Secret reports whether this answer is never written down. It is asked for
// immediately before the run that needs it, kept in memory for that run, and
// forgotten — so it is also the one required variable that does not stop the
// program from being ready.
func (v *Variable) Secret() bool { return v.Shape() == TypeSecret }

// Matches reports whether s satisfies the declared pattern. No pattern accepts
// anything.
func (v *Variable) Matches(s string) bool { return v.re == nil || v.re.MatchString(s) }

// Var finds a variable by name.
func (s *Spec) Var(name string) *Variable { return s.byName[name] }

// Name is the installer's own title, translated.
func (s *Spec) Name() string { return i18n.T(s.UI.Title) }

// Strings is every word this tree says, in the order it says them, with
// duplicates dropped.
//
// It is the list a translator works from, and the reason there is no separate
// file listing what needs translating: the strings are the yaml's own, and
// asking the loaded tree for them means the list can never fall behind it.
func (s *Spec) Strings() []string {
	var out []string
	seen := map[string]bool{}
	add := func(texts ...string) {
		for _, t := range texts {
			if t = strings.TrimSpace(t); t != "" && !seen[t] {
				seen[t] = true
				out = append(out, t)
			}
		}
	}
	add(s.UI.Title, s.UI.Console)
	for _, m := range s.Modes {
		add(m.Title, m.Description, m.Confirm)
	}
	for _, p := range s.Presets {
		add(p.Title, p.Description)
		for _, o := range p.Options {
			add(o.Title, o.Description)
		}
	}
	for _, v := range s.Vars {
		add(v.Title, v.Description, v.Group, v.Free, v.Error)
	}
	for _, t := range s.Tasks {
		add(t.Name, t.Confirm)
	}
	return out
}

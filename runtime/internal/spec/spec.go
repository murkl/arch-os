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

// LangVar is the runtime's own setting, and the only key it writes into the
// answer file that no installer.yaml declared. Language is not something an
// installer's data can own: the words it is chosen with belong to the frame,
// not to the thing being installed.
const LangVar = "INSTALLER_LANG"

// Spec is a whole installer tree.
type Spec struct {
	Dir string // absolute, and never written to

	UI      UI
	Presets []*Preset
	Vars    []*Variable

	// Stages are the phases of an installation, in the order they happen. Every
	// task names one; that is what puts it in the run and where.
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

	// Confirm is the last thing read before the first task runs, with {{VAR}}
	// filled in from the answers — the sentence that says which disk is about to
	// be erased.
	Confirm string `yaml:"confirm"`

	// Console is the sentence read on the way out of the interface, where the
	// machine keeps running. What the installer is called out there is something
	// only the tree can know, and somebody who has just left it is looking at a
	// bare prompt. Empty leaves that row off, which is right for an image where
	// there is nothing behind the interface.
	Console string `yaml:"console"`
}

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
}

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

	// Confirm is asked before this one runs, as a yes or no in the frame.
	// Declining skips it and the run carries on — which is what makes an
	// offer ("reboot now?") a unit like any other rather than a page of its own.
	Confirm string `yaml:"confirm"`

	// Quits marks a task the program does not come back from — a reboot. The
	// frame stops drawing rather than waiting for output nobody will read.
	Quits bool `yaml:"quits"`

	// TTY hands this one the terminal: it draws over the interface, keyboard
	// and all, and the frame comes back untouched when it exits. For the one
	// kind of unit that is a session rather than a step — a shell in the system
	// that was just installed.
	TTY bool `yaml:"tty"`

	id   string
	path string
	cond []*condition
}

func (t *Task) Label() string { return i18n.T(t.Name) }

// ID is the folder this task was read from, which is also the name other tasks
// reach it by in their needs.
func (t *Task) ID() string { return t.id }

// Path is the script it runs, absolute.
func (t *Task) Path() string { return t.path }

// Asks reports whether this one is offered rather than simply run.
func (t *Task) Asks() bool { return t.Confirm != "" }

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

	re   *regexp.Regexp
	cond []*condition
}

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

// ConfirmText is the last sentence before the first task, translated and
// with {{VAR}} filled in from the answers.
func (s *Spec) ConfirmText(get func(string) string) string {
	return strings.TrimSpace(Expand(i18n.T(s.UI.Confirm), get))
}

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
	add(s.UI.Title, s.UI.Confirm, s.UI.Console)
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

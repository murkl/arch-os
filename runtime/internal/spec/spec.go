// Package spec is the installer tree, read into memory: what the installer is
// called, what it needs to know, and what it does.
//
// A tree is one installer.yaml and the tasks beside it. Everything in it is
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

// What a tree is made of: one file that says what the installer is, and one
// folder holding the work, a unit per subfolder.
const (
	FileInstaller = "installer.yaml"
	TaskDir       = "tasks"
	TaskFile      = "task.yaml"
	TaskScript    = "task.sh"
)

// SharedPrefix marks a folder under tasks/ that is not one: a place for what
// several of them share — the library, the catalogs, data files. One character,
// and no list of exceptions to keep in the runtime.
const SharedPrefix = "_"

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

	// Wlan is how this tree finds and joins a wireless network, or nil when it
	// declares none.
	Wlan *Wlan

	// Leave is what this machine is offered when the interface is finished with
	// it, or nil when the tree declares nothing — in which case the program
	// simply exits, as any program does.
	Leave *Leave

	// Stages are the phases of an installation, in the order they happen. Every
	// task names one; that is what puts it in the run and where.
	Stages []string

	// Tasks, already in the order they run: by stage, and inside a stage by what
	// they declared they need. Sorted once when the tree is loaded, so there is
	// one order and everything downstream reads it rather than works it out
	// again.
	Tasks []*Task

	// Preflight is the one task that belongs to no stage: it runs at startup,
	// before anything is asked bar the few questions a tree marks `first`, and a
	// failure is a wall.
	Preflight *Task

	// Lib is the shell every script of this tree is given before its own, and
	// Locales the folder its catalogs live in. Both optional, both named by
	// installer.yaml — the runtime knows they exist, never what is in them.
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
}

// Wlan is how this tree finds and joins a wireless network, declared inline
// under the `wlan:` key in installer.yaml. A tree that declares none leaves
// Spec.Wlan nil, and the interface never offers the screen: not every
// installer needs one, and nothing downstream assumes it does.
//
// Only the commands live here — the screen, the network list and the
// passphrase prompt are the runtime's own and the same for any tree; what is
// declared is purely a property of the distribution being installed.
type Wlan struct {
	Title       string `yaml:"title"`
	Description string `yaml:"description"`

	// Check is the one required field: whether there is internet at all.
	Check string `yaml:"check"`

	// Device, Scan, Networks and Connect are what it takes to actually join a
	// network. A tree may declare only Check, which means "tell me if I am
	// offline" and nothing more — see Joinable.
	Device   string `yaml:"device"`
	Scan     string `yaml:"scan"`
	Networks string `yaml:"networks"`
	Connect  string `yaml:"connect"`
}

func (w *Wlan) Label() string { return i18n.T(w.Title) }
func (w *Wlan) Help() string  { return i18n.T(w.Description) }

// Joinable reports whether the tree described enough to actually connect, or
// only a check.
func (w *Wlan) Joinable() bool {
	return w.Device != "" && w.Networks != "" && w.Connect != ""
}

// Leave is how this machine is put down, declared inline under the `leave:` key
// in installer.yaml.
//
// A tree that declares it is saying that leaving the interface is not quitting a
// program: the machine booted to run this and has nothing else to do, so the way
// out is a restart or a shutdown and the interface offers those instead of an
// exit. A tree that declares none leaves the program exiting the way anything
// does, which is right for an installer run from a shell somebody is sitting in.
//
// Only the commands live here. What the page looks like, what the two rows are
// called and in which language is the runtime's own and the same for any tree;
// how a machine is restarted is not.
type Leave struct {
	Restart  string `yaml:"restart"`
	Shutdown string `yaml:"shutdown"`

	// Console is the way out that leaves the machine running: the installer
	// stops and hands the terminal back to whatever was behind it. Its value is
	// the sentence saying how to start it again, because what the installer is
	// called out there is something only the tree can know — and somebody who
	// has just left it is looking at a bare prompt.
	//
	// Declaring nothing leaves the row off, which is right for an image where
	// there is genuinely nothing behind the interface.
	Console string `yaml:"console"`
}

// Offers reports whether this tree named anything to actually do. A block with
// nothing in it is nothing to offer, and is refused when the tree is loaded
// rather than shown as an empty page.
func (l *Leave) Offers() bool {
	return l != nil && (l.Restart != "" || l.Shutdown != "" || l.Console != "")
}

// ConsoleHelp is the sentence under that row: what to type to be back here.
func (l *Leave) ConsoleHelp() string { return i18n.T(l.Console) }

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
	add(s.UI.Title, s.UI.Confirm)
	if s.Leave != nil {
		add(s.Leave.Console)
	}
	if s.Wlan != nil {
		add(s.Wlan.Title, s.Wlan.Description)
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
	if s.Preflight != nil {
		add(s.Preflight.Name)
	}
	for _, t := range s.Tasks {
		add(t.Name, t.Confirm)
	}
	return out
}

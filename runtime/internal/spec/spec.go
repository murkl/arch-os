// Package spec is what a runtime and its modules declare about themselves,
// read into memory: what the runtime is called and which modules it offers,
// and for each module what it needs to know and what it does.
//
// A module is one yaml and the folders beside it. Everything in it is data. The
// runtime ships none of its own — without a module there is nothing to run,
// only a binary that says so and stops. That is the whole point of the split:
// this package knows the shape of the yaml, and nothing in the program below it
// knows a single thing about the system being installed.
package spec

import (
	"path"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"github.com/murkl/arch-os/runtime/internal/i18n"
)

// What a module is made of. Only the declaration has to be there; everything
// else is found by its own name, so a module turns a part of the program off by
// leaving the file or folder out rather than by declaring anything.
//
// The declaration is the one yaml in the folder's top level, whatever it is
// called. The convention is the module's own name — installer/installer.yaml,
// recovery/recovery.yaml — which is what lets two of them sit open in an editor
// and still be told apart, and there is nothing to configure because a folder
// holds one.
const (
	Ext        = ".yaml"     // the declaration: what the module is, asks, and does
	FileLib    = "lib.sh"    // shell put in front of every script
	DirTasks   = "tasks"     // the work, one folder per step
	DirHooks   = "hooks"     // everything around it, one script per hook
	DirLocales = "locales"   // one catalog per language the module speaks
	FileTask   = "task.yaml" // where a step belongs
	FileScript = "task.sh"   // what it does
	ScriptExt  = ".sh"
)

// The hooks, each a bash script in hooks/ called by its own name. This is
// everything the runtime does around the work: nothing here installs anything,
// and a module that leaves one out simply does not get that part.
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
// refused when the module loads, the way a misspelled yaml key is: a hook that is
// never called because its name has a typo in it is the worst kind of
// authoring bug, since everything loads and nothing happens.
var HookNames = []string{
	HookPreflight, HookOnline, HookDevice, HookNetworks, HookConnect,
	HookRestart, HookShutdown,
}

// The runtime's own setting: the one key it writes into a module's answer file
// that the module never declared. It is not something a module's data can own —
// the words the interface is read in are settled before a module has been
// chosen, and they are the same in every one of them.
//
// A module may not declare it, and may name it in a `conditions:`.
const LangVar = "RUNTIME_LANG"

// RuntimeVars is every name that belongs to the runtime rather than to a module.
var RuntimeVars = []string{LangVar}

// runtimeVar reports whether a name is one of them.
func runtimeVar(name string) bool { return slices.Contains(RuntimeVars, name) }

// Module is one whole program the runtime can run: everything one folder
// beside the binary declares about itself.
type Module struct {
	Dir  string // absolute, and never written to
	File string // the declaration in it, e.g. installer.yaml

	UI      UI
	Presets []*Preset
	Vars    []*Variable

	// Confirm is the last thing read before the first task runs, with {{VAR}}
	// filled in from the answers — the sentence that says which disk is about to
	// be erased.
	Confirm string

	// Stages are the phases the work happens in, in the order they happen. Every
	// task names one, which is what puts it in the run and where.
	Stages []string

	// Tasks, already in the order they run: by stage, and inside a stage by what
	// they declared they need. Sorted once when the module is loaded, so there is
	// one order and everything downstream reads it rather than works it out
	// again.
	Tasks []*Task

	// Lib is the shell every script of this module is given before its own, and
	// Locales the folder its catalogs live in. Both are whatever FileLib and
	// DirLocales turned out to be, or empty where the module has neither.
	Lib     string
	Locales string

	// Language names the variable whose answer also settles the words this
	// interface is read in — a module that asks where a machine is has asked which
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

// UI is what a module says about itself: the words that make the frame this
// program rather than the one beside it. What they all look like is not here —
// one wordmark and one colour belong to the runtime, not to any module in it.
// See Runtime.
type UI struct {
	Title string `yaml:"title"`

	// Description is what this program is, in one sentence, and Run what one
	// run of it is called.
	//
	// The description is read on the page that asks which of the programs beside
	// the binary to open; the name is read wherever the interface says what is
	// happening — the row that starts it, the last warning, the clock while it
	// runs. A module that names no run is an installation as far as the runtime
	// is concerned, which is right for one kind of module and wrong for every
	// other.
	Description string `yaml:"description"`
	Run         string `yaml:"run"`

	// Console is the sentence read on the way out of the interface, where the
	// machine keeps running. What the module is called out there is something
	// only the module can know, and somebody who has just left it is looking at a
	// bare prompt. Empty leaves that row off, which is right for an image where
	// there is nothing behind the interface.
	Console string `yaml:"console"`
}

// RunName is what one run of this module is called, translated. Empty where the
// module did not say, which the runtime can only read as an installation.
func (s *Module) RunName() string { return i18n.T(s.UI.Run) }

// Help is what this module is, in one sentence: the line under its row on the
// page that asks which of them to open.
func (s *Module) Help() string { return i18n.T(s.UI.Description) }

// ConfirmText is the last sentence before the first task, translated and with
// {{VAR}} filled in from the answers.
func (s *Module) ConfirmText(get func(string) string) string {
	return strings.TrimSpace(Expand(i18n.T(s.Confirm), get))
}

// Hook is the script this module put in hooks/ under that name, absolute, or
// empty where it has none.
func (s *Module) Hook(name string) string { return s.hooks[name] }

// Source is the shell that runs a script file, for the places that take shell
// rather than a path. Empty in, empty out — a hook a module does not have.
func Source(path string) string {
	if path == "" {
		return ""
	}
	return "source " + quote(path)
}

// Leaves reports whether this machine can be left at all: a module that says
// how is saying the machine booted to run it, so every way out of the interface
// asks what to do with the machine instead of quitting.
func (s *Module) Leaves() bool {
	return s.Hook(HookRestart) != "" || s.Hook(HookShutdown) != "" || s.UI.Console != ""
}

// ConsoleHelp is the sentence under the row that leaves the machine running:
// what to type to be back here.
func (s *Module) ConsoleHelp() string { return i18n.T(s.UI.Console) }

// Preset is one page of starting points: a question a machine with no answer
// file is asked before the real ones, answered by choosing one of the options
// under it. It is the only place a value arrives without being typed.
//
// A module may declare several, each a page of its own, asked in the order
// they are declared.
type Preset struct {
	ID          string          `yaml:"id"`
	Title       string          `yaml:"title"`
	Description string          `yaml:"description"`
	Options     []*PresetOption `yaml:"options"`
}

// PresetOption is one answer to that question: the values choosing it fills in.
// Nothing else about it survives being chosen — it is a set of answers, not a
// mode the module stays in.
type PresetOption struct {
	ID          string            `yaml:"id"`
	Title       string            `yaml:"title"`
	Description string            `yaml:"description"`
	Values      map[string]Scalar `yaml:"values"`

	// Asks names the one question choosing this row puts, for the starting
	// point that is not written down here but fetched: a code somebody was
	// handed, and a whole set of answers standing behind it.
	//
	// The variable it names is asked on the page every other question is asked
	// on, and being named here is its whole declaration — it is left out of the
	// opening run and off the settings page, because a code that has already
	// been used stands for nothing anybody would want to change.
	Asks string `yaml:"asks"`

	// Apply is shell run once that answer is given, and the row is not got past
	// until it has worked. It is how an answer becomes answers: it writes them
	// into the answer file, which the runtime reads back — see Runner.Import.
	Apply string `yaml:"apply"`
}

// Fetches reports whether this row asks something before it fills anything in.
func (o *PresetOption) Fetches() bool { return o.Asks != "" }

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

	// Report is what the run stops to say once this one has run: the milestone
	// somebody watching a list of task names has no other way of recognising —
	// the work is done, and everything after it is offered rather than
	// required. {{VAR}} is filled in from the answers, and the first paragraph
	// is the headline, the way the opening logo's first block is its eyebrow.
	//
	// A run has at most a handful of these and most have none. It is not a
	// progress note: it is the page the run holds still on until somebody has
	// read it.
	Report string `yaml:"report"`

	// Shows names an answer to put on that page as a code to scan, and under it
	// as itself. For the value that is of no use inside the frame — a link, a
	// key — because the machine it is wanted on is the one in somebody's hand.
	//
	// The value is read back out of the answer file after this task has run, so
	// the task itself is what puts it there. Empty is not a failure: a page that
	// has nothing to show simply shows its words.
	Shows string `yaml:"shows"`

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

// Reports reports whether the run stops on a page of its own once this one has
// run.
func (t *Task) Reports() bool { return t.Report != "" }

// ReportText is that page's words, translated and with the answers filled in:
// the headline first, then whatever else it has to say.
func (t *Task) ReportText(get func(string) string) (headline, body string) {
	text := strings.TrimSpace(Expand(i18n.T(t.Report), get))
	headline, body, _ = strings.Cut(text, "\n\n")
	return headline, strings.TrimSpace(body)
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

// Variable is one thing a module needs to know, and everything known
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
	// the network screen, before the module's own check of the machine, before the
	// starting point is chosen. For the answer that everything after it is typed
	// on: a wireless passphrase given on a keyboard nobody chose is not the
	// passphrase, and there is nothing to be done about that afterwards.
	//
	// It is a promise a module should make sparingly. Every question here is a
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

	// Apply puts this answer into effect on the machine the runtime is running
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

// Deferred reports whether this value is one the opening run of questions has
// no business asking. Nothing declares it: being named by a task's `asks:` or
// `shows:`, or by a preset option's `asks:`, is the declaration.
//
// It is the second kind of required value that does not stop the program from
// being ready, and for the same reason a secret is the first: there is no
// answering it yet, or no point answering it twice. A snapshot to go back to
// cannot be chosen, or shown on a settings page, while the disk holding it is
// still locked; a link a run has yet to produce is not a question at all.
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
// nothing gets a sentence naming the rule it broke, so a module is never obliged
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

// domain is every answer this question has, or nil where the module left that
// open — a name typed into a box, a list a command prints. It is what makes a
// guard something that can be reasoned about rather than only evaluated.
func (v *Variable) domain() []string {
	switch {
	case len(v.Values) > 0:
		return v.Values
	case v.Shape() == TypeBool:
		return []string{BoolTrue, BoolFalse}
	}
	return nil
}

// ID is the folder this module was read from. It is what runtime.yaml lists it
// as, the word that opens it from the command line, and the name its answers
// and its log are kept under — one identity, so there is nothing to keep in
// step.
func (s *Module) ID() string { return filepath.Base(s.Dir) }

// Var finds a variable by name.
func (s *Module) Var(name string) *Variable { return s.byName[name] }

// Name is the module's own title, translated.
func (s *Module) Name() string { return i18n.T(s.UI.Title) }

// Message is one thing a module says: the text, what it is, and the files it
// was read out of. The last two are all a translator has — the words arrive out
// of the module they belong to, one sentence at a time.
type Message struct {
	Text  string
	Note  string
	Files []string
}

// Messages is every word this module says, in the order it says them, with
// duplicates dropped.
//
// It is the list a translator works from, and the reason there is no separate
// file listing what needs translating: the strings are the yaml's own, and
// asking the loaded module for them means the list can never fall behind it.
func (s *Module) Messages() []Message {
	var out []Message
	at := map[string]int{}
	add := func(file, note, text string) {
		text = strings.TrimSpace(text)
		if text == "" {
			return
		}
		// The same sentence in two places is one message said twice, and both
		// places are worth naming.
		if i, ok := at[text]; ok {
			if !slices.Contains(out[i].Files, file) {
				out[i].Files = append(out[i].Files, file)
			}
			return
		}
		at[text] = len(out)
		out = append(out, Message{Text: text, Note: note, Files: []string{file}})
	}

	decl := s.File
	add(decl, "what this program is called", s.UI.Title)
	add(decl, "what it is, in one sentence, on the page that offers it", s.UI.Description)
	add(decl, "what one run of it is called", s.UI.Run)
	add(decl, "how to get back in, read on the way out to the console", s.UI.Console)
	add(decl, "the last thing read before the first task runs", s.Confirm)
	for _, p := range s.Presets {
		add(decl, "starting point "+p.ID+": the question", p.Title)
		add(decl, "starting point "+p.ID+": what it means", p.Description)
		for _, o := range p.Options {
			add(decl, "starting point "+p.ID+", "+o.ID+": the row", o.Title)
			add(decl, "starting point "+p.ID+", "+o.ID+": what choosing it does", o.Description)
		}
	}
	for _, v := range s.Vars {
		add(decl, v.Name+": the question", v.Title)
		add(decl, v.Name+": what it means", v.Description)
		add(decl, v.Name+": the heading its row sits under", v.Group)
		add(decl, v.Name+": the row that opens a box for an answer of one's own", v.Free)
		add(decl, v.Name+": what a wrong answer is told", v.Error)
	}
	for _, t := range s.Tasks {
		file := path.Join(DirTasks, t.ID(), FileTask)
		add(file, "the step, as the run lists it", t.Name)
		add(file, "asked before the step runs", t.Confirm)
		add(file, "read once the step is done, and held on until somebody has", t.Report)
	}
	return out
}

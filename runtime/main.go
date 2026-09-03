// Command runtime draws an interface for programs that live beside it as files.
//
// On its own the binary does nothing: it draws an interface, asks questions,
// keeps the answers and runs shell in order, reporting where it broke. What is
// asked and what the shell does is a folder of yaml and scripts.
//
// One of those folders is a module, and they sit together in modules/ beside
// the binary. runtime.yaml beside them says what the product they add up to is
// called and what it looks like; each module says the rest for itself. Nothing
// about any particular operating system is compiled in, so the same binary
// drives a different product by sitting next to a different runtime.yaml and a
// different set of modules.
//
// That goes for the command line as well. Seven flags are the runtime's own —
// where to look, whether to ask, what to say about itself — and every other
// word one may carry is declared by a module and means whatever that module
// says it means.
package main

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/murkl/arch-os/runtime/internal/cli"
	"github.com/murkl/arch-os/runtime/internal/i18n"
	"github.com/murkl/arch-os/runtime/internal/logging"
	"github.com/murkl/arch-os/runtime/internal/runner"
	"github.com/murkl/arch-os/runtime/internal/spec"
	"github.com/murkl/arch-os/runtime/internal/store"
	"github.com/murkl/arch-os/runtime/locales"
	"github.com/murkl/arch-os/runtime/tui"
)

// version is set by the build (see the Makefile).
var version = "dev"

// The answers and the log live beside whoever started the program, never inside
// a module — which may be a read-only medium or a mounted image. A module's are
// named after the module, so two of them started from the same folder keep
// their own; the runtime's own answers are named after the runtime, beside
// them, and hold what is settled before any module has been chosen.
const (
	confExt = ".conf"
	logExt  = ".log"

	runtimeConf = "runtime" + confExt
)

// The runtime's own flags: the only names on a command line that are compiled
// into this program. Everything else one may carry is a module's, read out of
// its declaration — see spec.Module.Flags.
const (
	flagForce   = "force"
	flagConf    = "conf"
	flagDir     = "dir"
	flagVersion = "version"
	flagHelp    = "help"
	flagShort   = "h"
	flagCheck   = "check"
	flagStrings = "strings"
)

// own is the runtime's flags in the order --help lists them: what a run does,
// then where it reads and writes, then what it says about itself, and last the
// two that are for a build script rather than for a machine.
func own() []spec.Flag {
	return []spec.Flag{
		{Name: flagForce, Title: i18n.T("Run without asking, on the answers there already.")},
		{Name: flagConf, Value: "path", Title: i18n.T("Where the answers are kept.")},
		{Name: flagDir, Value: "path", Title: i18n.T("Where runtime.yaml and the modules folder are.")},
		{Name: flagVersion, Title: i18n.T("Print the version and stop.")},
		{Name: flagHelp, Alias: flagShort, Title: i18n.T("This page, or what one module takes.")},
		{Name: flagCheck, Title: i18n.T("Load everything, say what it holds, change nothing.")},
		{Name: flagStrings, Title: i18n.T("Print one module's translation template.")},
	}
}

func main() {
	if err := start(os.Args[1:]); err != nil {
		die(err)
	}
}

// start reads the command line and does what it says.
//
// It is read in two passes, because half of it is not known yet: which flags
// there are depends on which modules are beside the binary, and where those are
// is itself something the line may say. So the first pass reads only that, and
// the second reads the whole line against everything the modules turned out to
// declare.
func start(args []string) error {
	// A language before anything else, so even the message saying there is
	// nothing here to run is in one. Only the runtime's own catalogs exist this
	// early.
	i18n.Activate(i18n.Match(locale(), codes(i18n.Discover(locales.FS))), locales.FS)

	early := cli.Early(args, own())
	// Answered before anything is loaded: a version is what this binary is,
	// which is true of a binary standing on its own with no product beside it.
	if early.On(flagVersion) {
		fmt.Println(version)
		return nil
	}

	rt, err := spec.LoadRuntime(early.Value(flagDir))
	if err != nil {
		return err
	}
	mods, err := load(rt)
	if err != nil {
		return err
	}
	flags, err := line(mods)
	if err != nil {
		return err
	}

	cmd, err := cli.Parse(args, flags)
	if err != nil {
		return err
	}
	mod, err := pick(rt, mods, cmd.Module)
	if err != nil {
		return err
	}

	switch {
	case cmd.On(flagHelp):
		fmt.Print(help(rt, mods, mod, early.Value(flagConf)))
		return nil
	case cmd.On(flagCheck):
		return inspect(rt, only(mods, mod))
	case cmd.On(flagStrings):
		return catalog(rt, only(mods, mod))
	}
	return run(rt, only(mods, mod), cmd)
}

// line is every flag one command line may carry: the runtime's own, and each
// module's laid beside them.
//
// A name two modules both declare is one flag here and is carried by whichever
// module is opened, which is what lets a switch that simulates a run mean the
// same thing in every module that has one. A name the runtime already uses is
// refused: the two are declared in places that cannot see each other — one
// compiled in, one read out of a folder — and this is where they meet.
func line(mods []*spec.Module) ([]spec.Flag, error) {
	flags := own()
	for _, mod := range mods {
		if name := cli.Collide(flags, mod.Flags()); name != "" {
			return nil, fmt.Errorf("%s: --%s belongs to the runtime", mod.ID(), name)
		}
	}
	lists := [][]spec.Flag{flags}
	for _, mod := range mods {
		lists = append(lists, mod.Flags())
	}
	return cli.Union(lists...)
}

// pick is the module a command line named, or nil where it named none. A word
// that is not one of them is said to be, with everything on offer under it.
func pick(rt *spec.Runtime, mods []*spec.Module, id string) (*spec.Module, error) {
	if id == "" {
		return nil, nil
	}
	for _, mod := range mods {
		if mod.ID() == id {
			return mod, nil
		}
	}
	return nil, fmt.Errorf("%s\n%s",
		i18n.T("No module called %s.", id),
		i18n.T("This one offers %s.", strings.Join(rt.Modules, ", ")))
}

// only narrows a run to the module it is about, or leaves every one of them
// where none was named — which is the question the interface then asks.
func only(mods []*spec.Module, mod *spec.Module) []*spec.Module {
	if mod == nil {
		return mods
	}
	return []*spec.Module{mod}
}

// help is the page a run puts up when it is asked what it is rather than told
// what to do.
func help(rt *spec.Runtime, mods []*spec.Module, mod *spec.Module, conf string) string {
	// The words a module says are its own, so the page is read in the language
	// the interface would have opened in.
	sources := catalogs(mods...)
	i18n.Activate(language(saved(conf).Code(), i18n.Discover(sources...)), sources...)
	return cli.Page{
		Runtime: rt, Modules: mods, Module: mod,
		Flags: own(), Command: command(rt), Version: version,
	}.Render()
}

// command is what --help says to type. A product may name it, for the machine
// that reaches this binary through a launcher under another name; otherwise it
// is the name this run was started by, which is right everywhere else.
func command(rt *spec.Runtime) string {
	if rt.Help.Command != "" {
		return rt.Help.Command
	}
	return filepath.Base(os.Args[0])
}

// inspect loads everything a folder holds — what the product is called, and
// every module it offers or the one that was named — and says what it found,
// without touching anything. The same load the program does at startup, so
// everything it refuses would have stopped the program too, which is what makes
// it worth running from a build script.
func inspect(rt *spec.Runtime, mods []*spec.Module) error {
	reportRuntime(rt)
	unread := 0
	for _, mod := range mods {
		report(mod)
		n, err := reportUnread(mod)
		if err != nil {
			return err
		}
		unread += n
	}
	// The one thing here that is a verdict rather than a description, so this
	// fails where a build script runs it — see spec.Unread.
	if unread > 0 {
		return fmt.Errorf("%d question(s) asked where nothing reads the answer", unread)
	}
	return nil
}

// reportUnread names every question this module asks under conditions no task
// that reads it can run under, and how many there were.
func reportUnread(mod *spec.Module) (int, error) {
	unread, err := mod.Unread()
	if err != nil {
		return 0, err
	}
	for _, u := range unread {
		fmt.Printf("  %-10s %s\n", "unread", u)
	}
	return len(unread), nil
}

// reportRuntime is what the runtime says about itself, printed.
func reportRuntime(rt *spec.Runtime) {
	fmt.Printf("%s\n", rt.File)
	fmt.Printf("  name       %s\n", rt.Name)
	fmt.Printf("  accent     %s\n", rt.Accent)
	fmt.Printf("  logo       %d lines\n", len(strings.Split(strings.TrimRight(rt.Logo, "\n"), "\n")))
	fmt.Printf("  modules    %s\n", strings.Join(rt.Modules, " "))
}

// report is what one module holds, printed.
func report(mod *spec.Module) {
	required, secret := 0, 0
	for _, v := range mod.Vars {
		if v.Required {
			required++
		}
		if v.Secret() {
			secret++
		}
	}
	sources := catalogs(mod)
	langs := i18n.Discover(sources...)
	names := make([]string, len(langs))
	for i, l := range langs {
		names[i] = l.Code
	}
	fmt.Printf("%s\n", filepath.Join(mod.Dir, mod.File))
	fmt.Printf("  title      %s\n", mod.UI.Title)
	fmt.Printf("  variables  %d (%d required, %d secret)\n", len(mod.Vars), required, secret)
	fmt.Printf("  presets    %d\n", len(mod.Presets))
	fmt.Printf("  stages     %s\n", strings.Join(mod.Stages, " "))
	fmt.Printf("  tasks      %d\n", len(mod.Tasks))
	fmt.Printf("  hooks      %s\n", strings.Join(hooks(mod), " "))
	fmt.Printf("  flags      %s\n", strings.Join(taken(mod), " "))
	fmt.Printf("  languages  %s\n", strings.Join(names, " "))

	// The order they run in is worked out rather than written down anywhere.
	for i, t := range mod.Tasks {
		fmt.Printf("  %2d. %-10s %s\n", i+1, t.Stage, t.ID())
	}

	// A catalog whose keys have drifted from the yaml shows up here as a
	// coverage that dropped, which is the only way a stale translation is
	// noticed.
	msgs := mod.Messages()
	for _, l := range langs {
		if l.Code == i18n.SourceLang {
			continue
		}
		i18n.Activate(l.Code, sources...)
		done := 0
		for _, m := range msgs {
			if i18n.Has(m.Text) {
				done++
			}
		}
		fmt.Printf("  %-10s %d of %d strings translated\n", l.Code, done, len(msgs))
	}
}

// taken is what this module accepts on the command line, as it is written
// there — so a flag that is not being read because of a typo in its name is
// visible as one missing from this line.
func taken(mod *spec.Module) []string {
	flags := mod.Flags()
	out := make([]string, len(flags))
	for i, f := range flags {
		out[i] = "--" + f.Name
	}
	return out
}

// load reads every module the runtime offers, in the order it offers them.
//
// All of them, whichever one a run turns out to be about. A command line cannot
// be read until it is known what the words in it may be, and that is declared
// module by module. A release ships its modules together anyway, so one that
// will not load is a broken release, and saying so at startup beats a row that
// fails when somebody chooses it.
func load(rt *spec.Runtime) ([]*spec.Module, error) {
	out := make([]*spec.Module, 0, len(rt.Modules))
	for _, name := range rt.Modules {
		mod, err := spec.Load(rt.Path(name))
		if err != nil {
			return nil, fmt.Errorf("%s: %w", name, err)
		}
		out = append(out, mod)
	}
	return out, nil
}

func run(rt *spec.Runtime, mods []*spec.Module, cmd *cli.Command) error {
	conf := cmd.Value(flagConf)
	// A run nobody is watching has to be about something. There is no asking
	// which module to open when there is nothing to ask with, so the one thing
	// --force cannot supply is the one thing it insists on.
	forced := cmd.On(flagForce)
	if forced && len(mods) > 1 {
		return fmt.Errorf("%s\n%s",
			i18n.T("--%s runs one module without asking anything, so it has to be told which.", flagForce),
			i18n.T("This one offers %s.", strings.Join(rt.Modules, ", ")))
	}

	// The language is asked before a module is opened, so it is offered in every
	// language any of them speaks and their catalogs are laid over the runtime's
	// until one has been. Opening a module narrows them to its own.
	sources := catalogs(mods...)
	langs := i18n.Discover(sources...)

	lang := saved(conf)
	i18n.Activate(language(lang.Code(), langs), sources...)

	opening := &tui.Opening{
		Runtime: rt, Modules: mods, Lang: lang, Langs: langs, Sources: sources, Forced: forced,
	}
	return tui.Run(opening, func(mod *spec.Module) (*tui.Program, error) {
		return open(mod, conf, cmd, forced)
	}, version)
}

// saved is the runtime's own answers: the language, kept for every module.
//
// It sits in the folder a module's answers sit in, so that one folder holds one
// product's files and nothing else.
func saved(conf string) *store.Language {
	beside := "."
	if conf != "" {
		beside = filepath.Dir(conf)
	}
	if abs, err := filepath.Abs(beside); err == nil {
		beside = abs
	}
	return store.NewLanguage(filepath.Join(beside, runtimeConf))
}

// open makes one module runnable: the answers it keeps and the file they
// survive in, the log, and the runner that joins the module to the answers.
// Everything here is named after the module, which is why none of it happens
// before one has been chosen.
func open(mod *spec.Module, conf string, cmd *cli.Command, forced bool) (*tui.Program, error) {
	// What this module's answers and log are called, after the module itself.
	if conf == "" {
		conf = mod.ID() + confExt
	}
	conf, err := filepath.Abs(conf)
	if err != nil {
		return nil, err
	}

	st := store.New(mod, conf)
	st.SetFacts(version)
	if err := st.Load(); err != nil {
		return nil, err
	}

	// Opened before the first page of this module is drawn — and only now,
	// because where it goes follows where the answers go.
	logPath := filepath.Join(filepath.Dir(conf), mod.ID()+logExt)
	if err := logging.Init(logPath); err != nil {
		return nil, err
	}
	st.SetFact(store.ModuleLogVar, logPath)
	logging.Info("%s %s", mod.UI.Title, version)

	// The command line over the file: a value given now is somebody at this
	// machine saying so, and a value in the file is what it said last time.
	given, err := apply(mod, st, cmd)
	if err != nil {
		return nil, err
	}

	// This module's catalogs are laid over the runtime's, so a module may reword
	// anything. The language itself is the runtime's and is already settled: it
	// is written into these answers so that every script gets it, not asked
	// again.
	sources := catalogs(mod)
	langs := i18n.Discover(sources...)
	i18n.Activate(i18n.Current(), sources...)
	st.Set(spec.LangVar, i18n.Current())

	rn := runner.New(mod, st)
	if err := fetch(mod, st, rn, given); err != nil {
		return nil, err
	}

	// The answers survived a restart in the file; their effect on the live system
	// did not.
	rn.Settle()

	if forced {
		if err := ready(st); err != nil {
			return nil, err
		}
	}
	return &tui.Program{Module: mod, Store: st, Runner: rn, Langs: langs, Sources: sources}, nil
}

// apply takes what the command line said and makes it this module's: every
// option under its own name, and every question a flag answered.
//
// A value given here is held to exactly the rule the same value typed at a
// prompt is held to, and a wrong one stops the run before it starts rather than
// reaching a script — which is the whole point of a run nobody is watching.
//
// What comes back is which questions the line answered, because that is the one
// thing the file it was read over cannot say.
func apply(mod *spec.Module, st *store.Store, cmd *cli.Command) (map[string]bool, error) {
	// The options first, defaults and all, so every script sees each of them
	// under its own name whether the line mentioned it or not.
	for _, o := range mod.Options {
		value := o.Default.String()
		if cmd.Has(o.Flag) {
			value = cmd.Value(o.Flag)
		}
		st.SetFact(o.Name, value)
	}
	given := map[string]bool{}
	for _, v := range mod.Vars {
		if v.Flag == "" || !cmd.Has(v.Flag) {
			continue
		}
		value := cmd.Value(v.Flag)
		if why := st.Invalid(v, value); why != "" {
			return nil, fmt.Errorf("--%s: %s", v.Flag, why)
		}
		st.Set(v.Name, value)
		given[v.Name] = true
		if !v.Secret() {
			logging.Info("--%s: %s", v.Flag, value)
		}
	}
	return given, nil
}

// fetch takes the starting point that is not written down but fetched, where
// the command line gave the code that stands for it.
//
// A preset row with an `asks:` is one question and a whole configuration behind
// it: in the interface it is chosen by picking the row and typing the code.
// Giving the code outright is that same choice, made on the command line, so it
// does the same thing — the shell behind the row runs and what it wrote into the
// answer file is read back.
//
// Only for a code this run was given. One already in the answer file was
// fetched by the run that put it there, and fetching it again at every start
// would put a pastebin between this machine and its own answers.
func fetch(mod *spec.Module, st *store.Store, rn *runner.Runner, given map[string]bool) error {
	for _, p := range mod.Presets {
		for _, o := range p.Options {
			if !o.Fetches() || o.Apply == "" || !given[o.Asks] {
				continue
			}
			logging.Info("%s: %s", o.Asks, st.Get(o.Asks))
			if err := rn.Import(o.Apply)(); err != nil {
				return err
			}
			if err := rn.Imported(); err != nil {
				return err
			}
		}
	}
	return nil
}

// ready is what stops an unattended run before it starts: every question this
// module needs answered, answered.
//
// It is the one thing a run with nobody in front of it has to say for itself. A
// question that would have been a page is otherwise an empty string in a
// script's environment, and an installation that partitions a disk on one is
// worse than an installation that never began.
func ready(st *store.Store) error {
	unanswered := append(st.Missing(), st.Secrets()...)
	if len(unanswered) == 0 {
		return nil
	}
	lines := []string{i18n.T("%d question(s) here have no answer.", len(unanswered))}
	for _, v := range unanswered {
		// Named by the variable a script reads, and by the flag where there is
		// one: between them they say both what is missing and how to give it.
		how := ""
		if v.Flag != "" {
			how = "  --" + v.Flag
		}
		lines = append(lines, "  "+v.Name+how)
	}
	return fmt.Errorf("%s\n%s", i18n.T("Nothing to run without asking."), strings.Join(lines, "\n"))
}

// hooks is which of them this module actually has, so one that is not being
// called because of a typo in its name is visible as one missing from this line.
func hooks(mod *spec.Module) []string {
	var out []string
	for _, name := range spec.HookNames {
		if mod.Hook(name) != "" {
			out = append(out, name)
		}
	}
	return out
}

// catalogs is every source of words a run has: the runtime's own, and each
// module's laid over them. A module that declares none simply speaks the
// runtime's.
//
// Several modules at once is what the language page and the page asking which
// to open need, since none of them is the one this run is about yet.
func catalogs(mods ...*spec.Module) []fs.FS {
	out := []fs.FS{locales.FS}
	for _, mod := range mods {
		if mod.Locales != "" {
			out = append(out, os.DirFS(mod.Locales))
		}
	}
	return out
}

// language settles which one to speak: the stored choice if it is still on
// offer, otherwise whatever this machine's own locale comes closest to, and
// otherwise the language everything is written in.
func language(saved string, langs []i18n.Lang) string {
	all := codes(langs)
	for _, code := range all {
		if code == saved && saved != "" {
			return saved
		}
	}
	if code := i18n.Match(locale(), all); code != "" {
		return code
	}
	return i18n.SourceLang
}

// locale is what this machine says it speaks, in the order POSIX gives those
// answers.
func locale() string {
	for _, key := range []string{"LC_ALL", "LC_MESSAGES", "LANG"} {
		if v := os.Getenv(key); v != "" {
			return v
		}
	}
	return ""
}

func codes(langs []i18n.Lang) []string {
	out := make([]string, len(langs))
	for i, l := range langs {
		out[i] = l.Code
	}
	return out
}

// catalog writes the translation template for one module: every word it says,
// each with its translation left empty, in the order it says them. Redirect it
// to locales/<name>.pot, and a catalog for a language is that file with the
// right-hand side filled in — by hand, or on a platform that speaks po.
func catalog(rt *spec.Runtime, mods []*spec.Module) error {
	// One template belongs to one module. Which of several is not something to
	// guess at, so it is named on the command line rather than picked here.
	if len(mods) > 1 {
		return fmt.Errorf("%d modules here — name one: %s", len(mods), strings.Join(rt.Modules, ", "))
	}
	mod := mods[0]
	msgs := mod.Messages()
	entries := make([]i18n.Entry, 0, len(msgs))
	for _, m := range msgs {
		entries = append(entries, i18n.Entry{Text: m.Text, Note: m.Note, Refs: m.Files})
	}
	return i18n.Template(os.Stdout, mod.ID(), entries)
}

// die reports on stderr and in the log, then leaves. The one thing not shown
// inside the interface, because everything that gives the interface its name,
// its colours and its words is in what could not be read.
func die(err error) {
	msg := strings.TrimRight(err.Error(), "\n")
	logging.Error("%s", msg)
	fmt.Fprintln(os.Stderr, msg)
	os.Exit(1)
}

// Command runtime draws an interface for programs that live beside it as files.
//
// On its own the binary does nothing: it draws an interface, asks questions,
// keeps the answers and runs shell in order, reporting where it broke. What is
// asked and what the shell does is a folder of yaml and scripts.
//
// One of those folders is a module. runtime.yaml beside the binary says what
// the product they add up to is called, what it looks like, and which modules
// it offers; each module says the rest for itself. Nothing about any particular
// operating system is compiled in, so the same binary drives a different
// product by sitting next to a different runtime.yaml.
package main

import (
	"flag"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"

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

// Each knob has an environment variable of the same meaning, so an unattended
// run needs no command line.
const (
	dirVar  = "RUNTIME_DIR"
	confVar = "RUNTIME_CONF"
)

func main() {
	cmd := parse(os.Args[1:])

	if cmd.version {
		fmt.Println(version)
		return
	}
	if cmd.check {
		if err := inspect(cmd.dir, cmd.module); err != nil {
			die(err)
		}
		return
	}
	if cmd.strings {
		if err := catalog(cmd.dir, cmd.module); err != nil {
			die(err)
		}
		return
	}
	if err := run(cmd.dir, cmd.conf, cmd.module); err != nil {
		die(err)
	}
}

// command is a command line, read: which module to open, and everything the
// flags say about where to find it and what to do with it.
type command struct {
	module  string
	dir     string
	conf    string
	version bool
	check   bool
	strings bool
}

// parse reads one.
func parse(args []string) command {
	var c command
	set := flag.NewFlagSet(filepath.Base(os.Args[0]), flag.ExitOnError)
	set.StringVar(&c.dir, "dir", os.Getenv(dirVar), "where runtime.yaml and its modules are, instead of beside this binary")
	set.StringVar(&c.conf, "conf", os.Getenv(confVar), "where the answers are kept")
	set.BoolVar(&c.version, "version", false, "print the version and exit")
	set.BoolVar(&c.check, "check", false, "load what is there, report what it holds, and exit")
	set.BoolVar(&c.strings, "strings", false, "print the translation template for one module, and exit")

	c.module, args = take(set, args)
	// ExitOnError: a flag it cannot read never comes back here.
	_ = set.Parse(args)
	return c
}

// take pulls the module out of a command line and hands back what is left.
//
// It may be written as a word or with the dashes an option would carry —
// `runtime installer` and `runtime --installer` are the same request — and it
// may stand anywhere the flags do, because the walk below steps over each flag
// and, where it takes one, over its value as well.
//
// Whether the word names a module at all is not decided here but by
// runtime.yaml, which is what makes adding one a line of yaml and a folder
// rather than a change to this program. -h and -help are the flag package's
// own: asking for usage is not asking for a module called help.
func take(set *flag.FlagSet, args []string) (string, []string) {
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if !strings.HasPrefix(arg, "-") {
			return arg, slices.Delete(slices.Clone(args), i, i+1)
		}
		name, _, attached := strings.Cut(strings.TrimLeft(arg, "-"), "=")
		if name == "" || name == "h" || name == "help" {
			break
		}
		f := set.Lookup(name)
		if f == nil {
			return name, slices.Delete(slices.Clone(args), i, i+1)
		}
		if !attached && !boolFlag(f) {
			i++ // the next word is this flag's value, not a module
		}
	}
	return "", args
}

// boolFlag reports whether a flag stands on its own, the way the flag package
// itself decides it.
func boolFlag(f *flag.Flag) bool {
	b, ok := f.Value.(interface{ IsBoolFlag() bool })
	return ok && b.IsBoolFlag()
}

// inspect loads everything a folder holds — what the product is called, and
// every module it offers or the one that was named — and says what it found,
// without touching anything. The same load the program does at startup, so
// everything it refuses would have stopped the program too, which is what makes
// it worth running from a build script.
func inspect(dir, id string) error {
	rt, err := spec.LoadRuntime(dir)
	if err != nil {
		return err
	}
	mods, err := load(rt, id)
	if err != nil {
		return err
	}
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

// load reads the modules a run is about: the one named on the command line, or
// every module the runtime offers when none was.
//
// All of them, because a release ships its modules together: one that will not
// load is a broken release, and saying so at startup beats a row that fails
// when somebody chooses it.
func load(rt *spec.Runtime, id string) ([]*spec.Module, error) {
	ids := rt.Modules
	if id != "" {
		if !rt.Has(id) {
			return nil, fmt.Errorf("%s\n%s",
				i18n.T("No module called %s.", id),
				i18n.T("This one offers %s.", strings.Join(rt.Modules, ", ")))
		}
		ids = []string{id}
	}
	out := make([]*spec.Module, 0, len(ids))
	for _, name := range ids {
		mod, err := spec.Load(rt.Path(name))
		if err != nil {
			return nil, fmt.Errorf("%s: %w", name, err)
		}
		out = append(out, mod)
	}
	return out, nil
}

func run(dir, conf, id string) error {
	// A language before anything else, so even the message saying there is
	// nothing here to run is in one. Only the runtime's own catalogs exist this
	// early.
	i18n.Activate(i18n.Match(locale(), codes(i18n.Discover(locales.FS))), locales.FS)

	// What this product is called, what it looks like, and what it offers. Read
	// before any of it, because it dresses the first frame — which is drawn
	// before a module has been chosen.
	rt, err := spec.LoadRuntime(dir)
	if err != nil {
		return err
	}

	mods, err := load(rt, id)
	if err != nil {
		return err
	}

	// The language is asked before a module is opened, so it is offered in every
	// language any of them speaks and their catalogs are laid over the runtime's
	// until one has been. Opening a module narrows them to its own.
	sources := catalogs(mods...)
	langs := i18n.Discover(sources...)

	// The runtime's own answers sit in the folder a module's answers sit in, so
	// that one folder holds one product's files and nothing else.
	beside := "."
	if conf != "" {
		beside = filepath.Dir(conf)
	}
	beside, err = filepath.Abs(beside)
	if err != nil {
		return err
	}
	lang := store.NewLanguage(filepath.Join(beside, runtimeConf))
	i18n.Activate(language(lang.Code(), langs), sources...)

	opening := &tui.Opening{
		Runtime: rt, Modules: mods, Lang: lang, Langs: langs, Sources: sources,
	}
	return tui.Run(opening, func(mod *spec.Module) (*tui.Program, error) {
		return open(mod, conf)
	}, version)
}

// open makes one module runnable: the answers it keeps and the file they
// survive in, the log, and the runner that joins the module to the answers.
// Everything here is named after the module, which is why none of it happens
// before one has been chosen.
func open(mod *spec.Module, conf string) (*tui.Program, error) {
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
	// The environment first, then the file: a written answer is one this machine
	// gave, an inherited variable as often an accident as an instruction.
	st.LoadEnv()
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

	// This module's catalogs are laid over the runtime's, so a module may reword
	// anything. The language itself is the runtime's and is already settled: it
	// is written into these answers so that every script gets it, not asked
	// again.
	sources := catalogs(mod)
	langs := i18n.Discover(sources...)
	i18n.Activate(i18n.Current(), sources...)
	st.Set(spec.LangVar, i18n.Current())

	// The answers survived a restart in the file; their effect on the live system
	// did not.
	rn := runner.New(mod, st)
	rn.Settle()

	return &tui.Program{Module: mod, Store: st, Runner: rn, Langs: langs, Sources: sources}, nil
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
func catalog(dir, id string) error {
	rt, err := spec.LoadRuntime(dir)
	if err != nil {
		return err
	}
	mods, err := load(rt, id)
	if err != nil {
		return err
	}
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

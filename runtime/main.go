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
// That goes for the command line as well. Two words are the runtime's own —
// --debug and --version — and every other word on it is the name of a module to
// open, which is what makes adding one a folder rather than a change here.
package main

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
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

// The two words on a command line that are the runtime's own. They are written
// with dashes or without, one or two, because everything else on the line is a
// module and a module is written either way too.
const (
	flagDebug   = "debug"
	flagVersion = "version"
)

func main() {
	if err := start(os.Args[1:]); err != nil {
		die(err)
	}
}

// start reads the command line and does what it says.
func start(args []string) error {
	// A language before anything else, so even the message saying there is
	// nothing here to run is in one. Only the runtime's own catalogs exist this
	// early.
	i18n.Activate(i18n.Match(locale(), codes(i18n.Discover(locales.FS))), locales.FS)

	cmd, err := parse(args)
	if err != nil {
		return err
	}
	// Answered before anything is loaded: a version is what this binary is,
	// which is true of a binary standing on its own with no product beside it.
	if cmd.version {
		fmt.Println(version)
		return nil
	}

	rt, err := spec.LoadRuntime("")
	if err != nil {
		return err
	}
	mods, err := load(rt)
	if err != nil {
		return err
	}
	mod, err := pick(rt, mods, cmd.module)
	if err != nil {
		return err
	}
	return run(rt, only(mods, mod), cmd.debug)
}

// command is a command line, read: the module it named, and the two words that
// are not one.
type command struct {
	// module is the module it named, or empty where it named none — which is
	// the question the interface then asks.
	module  string
	debug   bool
	version bool
}

// parse reads one.
//
// A module may be written as a word or with the dashes an option would carry —
// `runtime installer` and `runtime --installer` are the same request — and it
// may stand anywhere on the line. Whether the word names a module at all is not
// decided here but by what is in modules/, which is what keeps the list of them
// out of this program: anything that is not one of the runtime's own two words
// is the module, and a name nobody declared is refused by pick with everything
// on offer under it.
func parse(args []string) (command, error) {
	var c command
	for _, arg := range args {
		switch name := strings.TrimLeft(arg, "-"); name {
		case flagDebug:
			c.debug = true
		case flagVersion:
			c.version = true
		case "":
			return c, fmt.Errorf("%s", i18n.T("%q names nothing.", arg))
		default:
			if c.module != "" {
				return c, fmt.Errorf("%s", i18n.T("One module at a time: %s or %s.", c.module, name))
			}
			c.module = name
		}
	}
	return c, nil
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

// load reads every module the runtime offers, in the order it offers them.
//
// All of them, whichever one a run turns out to be about. A word on the command
// line is only a module because a folder of that name is there, so the folders
// have to be read before the line can be answered. A release ships its modules
// together anyway, so one that will not load is a broken release, and saying so
// at startup beats a row that fails when somebody chooses it.
func load(rt *spec.Runtime) ([]*spec.Module, error) {
	out := make([]*spec.Module, 0, len(rt.Modules))
	for _, name := range rt.Modules {
		if name == flagDebug || name == flagVersion {
			return nil, fmt.Errorf("%s: --%s is the runtime's own word and cannot open a module", name, name)
		}
		mod, err := spec.Load(rt.Path(name))
		if err != nil {
			return nil, fmt.Errorf("%s: %w", name, err)
		}
		out = append(out, mod)
	}
	return out, nil
}

func run(rt *spec.Runtime, mods []*spec.Module, debug bool) error {
	// The language is asked before a module is opened, so it is offered in every
	// language any of them speaks and their catalogs are laid over the runtime's
	// until one has been. Opening a module narrows them to its own.
	sources := catalogs(mods...)
	langs := i18n.Discover(sources...)

	lang := saved()
	i18n.Activate(language(lang.Code(), langs), sources...)

	opening := &tui.Opening{
		Runtime: rt, Modules: mods, Lang: lang, Langs: langs, Sources: sources,
	}
	return tui.Run(opening, func(mod *spec.Module) (*tui.Program, error) {
		return open(mod, debug)
	}, version)
}

// saved is the runtime's own answers: the language, kept for every module.
//
// It sits in the folder a module's answers sit in, so that one folder holds one
// product's files and nothing else.
func saved() *store.Language {
	beside, err := filepath.Abs(".")
	if err != nil {
		beside = "."
	}
	return store.NewLanguage(filepath.Join(beside, runtimeConf))
}

// open makes one module runnable: the answers it keeps and the file they
// survive in, the log, and the runner that joins the module to the answers.
// Everything here is named after the module, which is why none of it happens
// before one has been chosen.
func open(mod *spec.Module, debug bool) (*tui.Program, error) {
	// What this module's answers and log are called, after the module itself.
	conf, err := filepath.Abs(mod.ID() + confExt)
	if err != nil {
		return nil, err
	}

	st := store.New(mod, conf)
	st.SetFacts(version, debug)
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

// die reports on stderr and in the log, then leaves. The one thing not shown
// inside the interface, because everything that gives the interface its name,
// its colours and its words is in what could not be read.
func die(err error) {
	msg := strings.TrimRight(err.Error(), "\n")
	logging.Error("%s", msg)
	fmt.Fprintln(os.Stderr, msg)
	os.Exit(1)
}

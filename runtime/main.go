// Command installer is a runtime for an installer that lives beside it as files.
//
// On its own the binary installs nothing: it draws an interface, asks questions,
// keeps the answers and runs shell in order, reporting where it broke. What is
// asked and what the shell does is a yaml and the tasks beside it.
//
// Everything system-specific lives in that tree, so the same binary drives an
// installer for anything, and the tree is maintained and translated on its own.
package main

import (
	"flag"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"installer/internal/i18n"
	"installer/internal/logging"
	"installer/internal/runner"
	"installer/internal/spec"
	"installer/internal/store"
	"installer/locales"
	"installer/tui"
)

// version is set by the build (see the Makefile).
var version = "dev"

// The answers and the log live beside whoever started the program, never inside
// the installer tree — which may be a read-only medium or a mounted image. Both
// are named after the tree they belong to, so two trees started from the same
// folder keep their own: installer.yaml answers into installer.conf, and
// recovery.yaml beside it into recovery.conf.
const (
	confExt = ".conf"
	logExt  = ".log"
)

// Each knob has an environment variable of the same meaning, so an unattended
// run needs no command line.
const (
	dirVar  = "INSTALLER_DIR"
	confVar = "INSTALLER_CONF"
)

func main() {
	dir := flag.String("dir", os.Getenv(dirVar), "the installer tree to run, instead of the one beside this binary")
	conf := flag.String("conf", os.Getenv(confVar), "where the answers are kept")
	show := flag.Bool("version", false, "print the version and exit")
	check := flag.Bool("check", false, "load the installer, report what it holds, and exit")
	strs := flag.Bool("strings", false, "print the translation template for the installer, and exit")
	flag.Parse()

	if *show {
		fmt.Println(version)
		return
	}
	if *check {
		if err := inspect(*dir); err != nil {
			die(err)
		}
		return
	}
	if *strs {
		if err := catalog(*dir); err != nil {
			die(err)
		}
		return
	}
	if err := run(*dir, *conf); err != nil {
		die(err)
	}
}

// inspect loads every tree this binary would offer and says what it found,
// without touching anything. The same load the program does at startup, so
// everything it refuses would have stopped the installer — for checking a
// release from a build script.
func inspect(dir string) error {
	trees, err := loadTrees(dir)
	if err != nil {
		return err
	}
	for _, sp := range trees {
		report(sp)
	}
	return nil
}

// report is what one tree holds, printed.
func report(sp *spec.Spec) {
	required, secret := 0, 0
	for _, v := range sp.Vars {
		if v.Required {
			required++
		}
		if v.Secret() {
			secret++
		}
	}
	sources := catalogs(sp)
	langs := i18n.Discover(sources...)
	names := make([]string, len(langs))
	for i, l := range langs {
		names[i] = l.Code
	}
	fmt.Printf("%s\n", filepath.Join(sp.Dir, sp.File))
	fmt.Printf("  title      %s\n", sp.UI.Title)
	fmt.Printf("  variables  %d (%d required, %d secret)\n", len(sp.Vars), required, secret)
	fmt.Printf("  presets    %d\n", len(sp.Presets))
	fmt.Printf("  stages     %s\n", strings.Join(sp.Stages, " "))
	fmt.Printf("  tasks      %d\n", len(sp.Tasks))
	fmt.Printf("  hooks      %s\n", strings.Join(hooks(sp), " "))
	fmt.Printf("  languages  %s\n", strings.Join(names, " "))

	// The order they run in is worked out rather than written down anywhere.
	for i, t := range sp.Tasks {
		fmt.Printf("  %2d. %-10s %s\n", i+1, t.Stage, t.ID())
	}

	// A catalog whose keys have drifted from the yaml shows up here as a
	// coverage that dropped, which is the only way a stale translation is
	// noticed.
	msgs := sp.Messages()
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

// trees is every program this binary would offer, read and checked over. One
// that will not load stops the program here rather than when somebody chooses
// it: a release ships its programs together, so a broken one is a broken
// release.
func loadTrees(dir string) ([]*spec.Spec, error) {
	dirs, err := spec.Trees(dir)
	if err != nil {
		return nil, err
	}
	out := make([]*spec.Spec, 0, len(dirs))
	for _, d := range dirs {
		sp, err := spec.Load(d)
		if err != nil {
			return nil, err
		}
		out = append(out, sp)
	}
	return out, nil
}

func run(dir, conf string) error {
	// A language before anything else, so even the message saying no installer
	// was found is in one. Only the runtime's own catalogs exist this early.
	i18n.Activate(i18n.Match(locale(), codes(i18n.Discover(locales.FS))), locales.FS)

	trees, err := loadTrees(dir)
	if err != nil {
		return err
	}

	// The page that asks which of them to open is read in their own words, and
	// nothing has been chosen yet — so every tree's catalogs are laid over the
	// runtime's until one has been. Opening one narrows them to its own.
	sources := catalogs(trees...)
	i18n.Activate(i18n.Match(locale(), codes(i18n.Discover(sources...))), sources...)

	return tui.Run(trees, func(sp *spec.Spec) (*tui.Program, error) {
		return open(sp, conf)
	}, version)
}

// open makes one tree runnable: the answers it keeps and the file they survive
// in, the log, the words it is read in, and the runner that joins the tree to
// the answers. Everything here is named after the tree, which is why none of it
// happens before one has been chosen.
func open(sp *spec.Spec, conf string) (*tui.Program, error) {
	// What this tree's answers and log are called, after the tree itself.
	name := strings.TrimSuffix(sp.File, spec.SpecExt)
	if conf == "" {
		conf = name + confExt
	}
	conf, err := filepath.Abs(conf)
	if err != nil {
		return nil, err
	}

	st := store.New(sp, conf)
	st.SetFacts(version)
	// The environment first, then the file: a written answer is one this machine
	// gave, an inherited variable as often an accident as an instruction.
	st.LoadEnv()
	if err := st.Load(); err != nil {
		return nil, err
	}

	// Opened before the first page of this tree is drawn — and only now, because
	// where it goes follows where the answers go.
	logPath := filepath.Join(filepath.Dir(conf), name+logExt)
	if err := logging.Init(logPath); err != nil {
		return nil, err
	}
	st.SetFact("INSTALLER_LOG", logPath)
	logging.Info("%s %s", sp.UI.Title, version)

	// This tree's catalogs are laid over the runtime's, so a tree may reword
	// anything. A stored choice beats the machine's locale: somebody said so.
	sources := catalogs(sp)
	langs := i18n.Discover(sources...)
	i18n.Activate(language(st.Get(spec.LangVar), langs), sources...)
	st.Set(spec.LangVar, i18n.Current())

	// The answers survived a restart in the file; their effect on the live system
	// did not.
	rn := runner.New(sp, st)
	rn.Settle()

	return &tui.Program{Spec: sp, Store: st, Runner: rn, Langs: langs, Sources: sources}, nil
}

// hooks is which of them this tree actually has, so one that is not being called
// because of a typo in its name is visible as one missing from this line.
func hooks(sp *spec.Spec) []string {
	var out []string
	for _, name := range spec.HookNames {
		if sp.Hook(name) != "" {
			out = append(out, name)
		}
	}
	return out
}

// catalogs is every source of words a run has: the runtime's own, and each
// tree's laid over them. A tree that declares none simply speaks the runtime's.
//
// Several trees at once is what the page asking which to open needs, since none
// of them is the one this run is about yet.
func catalogs(trees ...*spec.Spec) []fs.FS {
	out := []fs.FS{locales.FS}
	for _, sp := range trees {
		if sp.Locales != "" {
			out = append(out, os.DirFS(sp.Locales))
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

// catalog writes the translation template for one tree: every word it says,
// each with its translation left empty, in the order it says them. Redirect it
// to locales/<name>.pot, and a catalog for a language is that file with the
// right-hand side filled in — by hand, or on a platform that speaks po.
func catalog(dir string) error {
	trees, err := loadTrees(dir)
	if err != nil {
		return err
	}
	// One template belongs to one tree. Which of several is not something to
	// guess at, so it is named with -dir rather than picked here.
	if len(trees) > 1 {
		return fmt.Errorf("%d trees here — name one with -dir", len(trees))
	}
	sp := trees[0]
	msgs := sp.Messages()
	entries := make([]i18n.Entry, 0, len(msgs))
	for _, m := range msgs {
		entries = append(entries, i18n.Entry{Text: m.Text, Note: m.Note, Refs: m.Files})
	}
	return i18n.Template(os.Stdout, strings.TrimSuffix(sp.File, spec.SpecExt), entries)
}

// die reports on stderr and in the log, then leaves. The one thing not shown
// inside the interface, because everything that gives the interface its name,
// its colours and its words is in the tree that could not be read.
func die(err error) {
	msg := strings.TrimRight(err.Error(), "\n")
	logging.Error("%s", msg)
	fmt.Fprintln(os.Stderr, msg)
	os.Exit(1)
}

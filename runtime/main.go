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
	"strconv"
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
	strs := flag.Bool("strings", false, "print an empty translation catalog for the installer")
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

// inspect loads a tree and says what it found, without touching anything. The
// same load the program does at startup, so everything it refuses would have
// stopped the installer — for checking a tree from a build script.
func inspect(dir string) error {
	dir, err := spec.Find(dir)
	if err != nil {
		return err
	}
	sp, err := spec.Load(dir)
	if err != nil {
		return err
	}
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
	fmt.Printf("%s\n", filepath.Join(dir, sp.File))
	fmt.Printf("  title      %s\n", sp.UI.Title)
	fmt.Printf("  variables  %d (%d required, %d secret)\n", len(sp.Vars), required, secret)
	fmt.Printf("  presets    %d\n", len(sp.Presets))
	if sp.Asked() {
		fmt.Printf("  modes      %s\n", strings.Join(modes(sp), " "))
	}
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
	msgs := sp.Strings()
	for _, l := range langs {
		if l.Code == i18n.SourceLang {
			continue
		}
		i18n.Activate(l.Code, sources...)
		done := 0
		for _, m := range msgs {
			if i18n.Has(m) {
				done++
			}
		}
		fmt.Printf("  %-10s %d of %d strings translated\n", l.Code, done, len(msgs))
	}
	return nil
}

func run(dir, conf string) error {
	// A language before anything else, so even the message saying no installer
	// was found is in one. Only the runtime's own catalogs exist this early.
	i18n.Activate(i18n.Match(locale(), codes(i18n.Discover(locales.FS))), locales.FS)

	dir, err := spec.Find(dir)
	if err != nil {
		return err
	}
	sp, err := spec.Load(dir)
	if err != nil {
		return err
	}

	// What this tree's answers and log are called, after the tree itself.
	name := strings.TrimSuffix(sp.File, spec.SpecExt)
	if conf == "" {
		conf = name + confExt
	}
	if conf, err = filepath.Abs(conf); err != nil {
		return err
	}

	st := store.New(sp, conf)
	st.SetFacts(version)
	// The environment first, then the file: a written answer is one this machine
	// gave, an inherited variable as often an accident as an instruction.
	st.LoadEnv()
	if err := st.Load(); err != nil {
		return err
	}
	// Settled before the first page, so every condition, every script and the
	// answer file read the same thing from the start: whatever was chosen last if
	// it is still on offer, otherwise the first the tree names.
	if sp.Mode(st.Get(spec.ModeVar)) == nil {
		st.Set(spec.ModeVar, sp.Modes[0].ID)
	}

	// Opened before the interface, so the first page is already recorded — and
	// only now, because where it goes follows where the answers go.
	logPath := filepath.Join(filepath.Dir(conf), name+logExt)
	if err := logging.Init(logPath); err != nil {
		return err
	}
	st.SetFact("INSTALLER_LOG", logPath)
	logging.Info("%s %s", sp.UI.Title, version)

	// The tree's catalogs are laid over the runtime's, so a tree may reword
	// anything. A stored choice beats the machine's locale: somebody said so.
	sources := catalogs(sp)
	langs := i18n.Discover(sources...)
	i18n.Activate(language(st.Get(spec.LangVar), langs), sources...)
	st.Set(spec.LangVar, i18n.Current())

	// The answers survived a restart in the file; their effect on the live system
	// did not.
	rn := runner.New(sp, st)
	rn.Settle()

	return tui.Run(sp, st, rn, version, langs, sources)
}

// modes is what this tree can do, in the order it offers it.
func modes(sp *spec.Spec) []string {
	out := make([]string, len(sp.Modes))
	for i, m := range sp.Modes {
		out[i] = m.ID
	}
	return out
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

// catalogs is every source of words this run has: the runtime's own, and the
// tree's laid over them. A tree that declares none simply speaks the runtime's.
func catalogs(sp *spec.Spec) []fs.FS {
	if sp.Locales == "" {
		return []fs.FS{locales.FS}
	}
	return []fs.FS{locales.FS, os.DirFS(sp.Locales)}
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

// catalog prints every word an installer says, with the right-hand side left
// empty: redirect it to locales/<code>.yaml and fill it in. Run again after the
// tree changes and the new strings are in the output.
func catalog(dir string) error {
	dir, err := spec.Find(dir)
	if err != nil {
		return err
	}
	sp, err := spec.Load(dir)
	if err != nil {
		return err
	}
	fmt.Printf("# Translation catalog for %s.\n", sp.UI.Title)
	fmt.Printf("# Fill in the right-hand side. Anything left empty stays as it is written here.\n")
	fmt.Printf("language: \"\"\n")
	fmt.Printf("messages:\n")
	for _, msg := range sp.Strings() {
		fmt.Printf("  %s: \"\"\n", quoteYAML(msg))
	}
	return nil
}

// quoteYAML renders one message as a yaml key, using a block of its own where
// the text runs over several lines.
func quoteYAML(s string) string {
	if !strings.Contains(s, "\n") {
		return strconv.Quote(s)
	}
	var b strings.Builder
	b.WriteString("? |-\n")
	for line := range strings.SplitSeq(strings.TrimRight(s, "\n"), "\n") {
		// The blank line between two paragraphs is written as a blank line, not
		// as four spaces: a catalog is edited and then linted like any other
		// yaml, and trailing whitespace is what a linter says first.
		if line != "" {
			b.WriteString("    ")
			b.WriteString(line)
		}
		b.WriteByte('\n')
	}
	return strings.TrimRight(b.String(), "\n") + "\n  "
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

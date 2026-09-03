// Command inspect is what a build script asks about a folder of modules.
//
// It loads a whole product the way the runtime does at startup — the
// runtime.yaml, and every module beside it or the one that was named — and then
// either says what it found or writes one module's translation template. Both
// are questions about a folder, not things a machine being installed ever needs,
// which is why they are here rather than on the binary that ships.
//
//	go run ./tools/inspect -dir ../.dev              # every module of a product
//	go run ./tools/inspect -dir ../.dev installer    # just that one
//	go run ./tools/inspect -dir ../.dev -strings installer > locales/installer.pot
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
	"github.com/murkl/arch-os/runtime/internal/spec"
	"github.com/murkl/arch-os/runtime/locales"
)

func main() {
	dir := flag.String("dir", "", "where runtime.yaml and the modules folder are")
	strs := flag.Bool("strings", false, "write one module's translation template instead of a report")
	flag.Parse()

	if err := run(*dir, flag.Arg(0), *strs); err != nil {
		fmt.Fprintln(os.Stderr, strings.TrimRight(err.Error(), "\n"))
		os.Exit(1)
	}
}

func run(dir, id string, template bool) error {
	rt, err := spec.LoadRuntime(dir)
	if err != nil {
		return err
	}
	mods, err := load(rt, id)
	if err != nil {
		return err
	}
	if template {
		return catalog(rt, mods)
	}
	return inspect(rt, mods)
}

// load reads the modules this run is about: the one that was named, or every
// module the runtime offers when none was.
func load(rt *spec.Runtime, id string) ([]*spec.Module, error) {
	ids := rt.Modules
	if id != "" {
		if !slices.Contains(ids, id) {
			return nil, fmt.Errorf("no module called %s — this one offers %s", id, strings.Join(ids, ", "))
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

// inspect says what a folder holds — what the product is called, and every
// module it offers or the one that was named — without touching anything. The
// same load the program does at startup, so everything it refuses would have
// stopped the program too, which is what makes it worth running from a build
// script.
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

// catalogs is every source of words a module has: the runtime's own, and the
// module's laid over them.
func catalogs(mod *spec.Module) []fs.FS {
	out := []fs.FS{locales.FS}
	if mod.Locales != "" {
		out = append(out, os.DirFS(mod.Locales))
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

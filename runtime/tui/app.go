// Package tui is the interface: one frame, a stack of pages inside it, and
// nothing above the shell layer that knows what a task is.
//
// It is the only half of the program a person ever sees, and it draws whatever
// module it was handed without knowing anything about what that module does.
// Every page is a screen — four methods, no state shared with its neighbours —
// and the frame around them belongs to the model alone, so there is exactly one
// place that decides what this program looks like and exactly one that can
// promise nothing escapes it.
//
// Three things are deliberately kept to one file each: palette.go names every
// colour, glyphs.go every character, and labels.go every word the interface
// says that did not come out of a module.
package tui

import (
	"fmt"
	"io/fs"

	"github.com/murkl/arch-os/runtime/internal/i18n"
	"github.com/murkl/arch-os/runtime/internal/logging"
	"github.com/murkl/arch-os/runtime/internal/runner"
	"github.com/murkl/arch-os/runtime/internal/spec"
	"github.com/murkl/arch-os/runtime/internal/store"

	tea "github.com/charmbracelet/bubbletea"
)

// Program is one module, opened: the answers it keeps, the runner that joins
// the two, and the words it is read in.
//
// What it takes to open one — where the answer file and the log go, what this
// machine has already been told — is the caller's business rather than the
// interface's, so the interface is handed the finished thing.
type Program struct {
	Module  *spec.Module
	Store   *store.Store
	Runner  *runner.Runner
	Langs   []i18n.Lang
	Sources []fs.FS
}

// Opening is everything a run has before a module has been opened: what the
// product is called and looks like, which modules it offers, every language any
// of them can be read in, and the one answer the runtime keeps for itself.
//
// It is Program's other half. Between them they are the whole of what the
// interface is handed: this before a module has been chosen, and that one
// afterwards.
type Opening struct {
	Runtime *spec.Runtime
	Modules []*spec.Module
	Lang    *store.Language
	Langs   []i18n.Lang
	Sources []fs.FS

	// Forced is a run with nobody in front of it: every question already
	// answered, and the interface asked to draw what is happening rather than
	// to ask anything. See app.forced.
	Forced bool
}

// Open opens one module, once it has been chosen. Nothing is opened before
// that: the answers, the log and the catalogs are all named after the module
// they belong to, and opening two would be a machine writing files for a
// program nobody asked for.
type Open func(*spec.Module) (*Program, error)

// app is what every screen shares: the module, the answers, and the runner that
// joins them. Screens hold a pointer to it rather than to each other.
type app struct {
	// What this product is called and what it looks like, the modules it offers
	// and the way one of them is opened. Several is a question the interface
	// puts after the language; one is opened on the way in and never mentioned.
	runtime *spec.Runtime
	modules []*spec.Module
	open    Open

	// lang is what the runtime remembers for every module: the words all of
	// them are read in, settled before any of them is opened.
	lang *store.Language

	module  *spec.Module
	store   *store.Store
	runner  *runner.Runner
	version string

	// The languages on offer and where their catalogs come from. Kept because
	// the language can be changed at any point in the run and every word on
	// screen has to follow.
	langs   []i18n.Lang
	sources []fs.FS

	// farewell is what to say on the terminal once the frame is gone: how to
	// start this installer again, for somebody who chose to leave it running.
	// Empty for every other way out — a machine on its way down is not reading.
	farewell string

	// first records whether this machine had answered anything when the program
	// started. It is read once, before the first save — after that the answer
	// file exists whatever happens, and the question "is this a first run" would
	// answer itself wrong for the rest of the session.
	first bool

	// forced is a run nobody is watching: --force on the command line, with
	// every question answered before the program started.
	//
	// It is not a second interface. The same pages run the same work in the same
	// order; what changes is that none of them stops to ask. Every question was
	// settled before the first frame — the run would not have got this far
	// otherwise, see ready in main.go — an offer is answered by the default it
	// declared, and a page that only has something to say is not held on.
	forced bool

	// failure is how such a run reports. Nobody is going to read a page, and a
	// script that started this one wants an exit status, so what went wrong is
	// carried back out of the interface and printed on the terminal it left.
	failure error
}

// Run shows the splash and then the interface, and returns when the user
// leaves. One program for both, because the splash fades into the first page
// and a fade cannot cross a program boundary — the terminal would drop out of
// the alternate screen in between. Choosing which module to open happens inside
// it for the same reason.
func Run(o *Opening, open Open, version string) error {
	// Which kind of terminal this is has to be settled here: the question is put
	// to the terminal itself, and from the next line on there is a key reader
	// running that would take the answer for somebody typing.
	Adapt()
	a := &app{
		runtime: o.Runtime, modules: o.Modules, lang: o.Lang,
		langs: o.Langs, sources: o.Sources,
		open: open, version: version, forced: o.Forced,
	}
	// The frame is dressed before there is a module to dress it with, and stays
	// dressed that way afterwards: the wordmark and the colour are the runtime's,
	// which is what makes every module read as one product.
	SetAccent(o.Runtime.Accent)
	// One module is no question: it is opened here, so the interface comes up on
	// its first page rather than on a list with a single row on it. So is one
	// named on the command line — that is the question, already answered.
	if len(o.Modules) == 1 {
		if err := a.enter(o.Modules[0]); err != nil {
			return err
		}
	}
	if _, err := tea.NewProgram(newModel(a, o.Runtime.Logo), tea.WithAltScreen()).Run(); err != nil {
		return err
	}
	// After the program, not inside it: the alternate screen is gone by now, so
	// this lands on the terminal the user is left sitting at rather than on a
	// frame that is about to be wiped.
	if a.farewell != "" {
		fmt.Println(a.farewell)
	}
	// A run nobody watched says how it went here, where there is a terminal
	// again and something that started it is waiting for an exit status.
	return a.failure
}

// enter opens a module and makes it the one this run is about: from here on the
// answers, the log and every word on screen belong to it.
//
// Choosing the module already open is not a second opening. It would rotate a
// log this run is already writing, and there is nothing to settle that the
// first one did not.
func (a *app) enter(mod *spec.Module) error {
	if a.module == mod {
		return nil
	}
	p, err := a.open(mod)
	if err != nil {
		return err
	}
	a.module, a.store, a.runner = p.Module, p.Store, p.Runner
	a.langs, a.sources = p.Langs, p.Sources
	a.first = !p.Store.Exists()
	return nil
}

// brand is what the frame is titled: the module this run is about, once one has
// been chosen. The pages in front of that — the language, the question of which
// module to open — belong to none of them, so they wear the runtime's own name.
func (a *app) brand() string {
	if a.module == nil {
		return a.runtime.Name
	}
	return a.module.Name()
}

// leaves reports whether this machine has to be asked about on the way out. A
// module nobody has opened yet has said nothing about the machine, so leaving
// the pages in front of one is leaving.
func (a *app) leaves() bool { return a.module != nil && a.module.Leaves() }

// speak puts the whole interface in a language and remembers the choice. It is
// the runtime's answer rather than a module's — it is settled before one is
// opened and it holds for all of them — and it is written into whichever module
// is open as well, so every script it runs is told what is on screen.
//
// Every word on screen is read through i18n at draw time, so there is nothing
// to rebuild: the next frame is simply in the new language.
func (a *app) speak(code string) tea.Cmd {
	i18n.Activate(code, a.sources...)
	a.lang.Set(code)
	if err := a.lang.Save(); err != nil {
		logging.Error("%s", err)
		return flashBad(err.Error())
	}
	if a.store == nil {
		return nil
	}
	a.store.Set(spec.LangVar, code)
	return a.save()
}

// speakLike puts the interface in whatever language an answer comes closest to,
// for the module that ties one of its own variables to the words on screen —
// see `language:` in a module's declaration.
//
// A locale is not a catalog, so the match is by language rather than by name:
// de_AT is German. An answer no catalog fits leaves the source language
// standing, which is what a module nobody has translated already is.
func (a *app) speakLike(value string) {
	codes := make([]string, len(a.langs))
	for i, l := range a.langs {
		codes[i] = l.Code
	}
	code := i18n.Match(value, codes)
	if code == "" {
		code = i18n.SourceLang
	}
	i18n.Activate(code, a.sources...)
	a.lang.Set(code)
	if err := a.lang.Save(); err != nil {
		logging.Error("%s", err)
	}
	a.store.Set(spec.LangVar, code)
}

// adopt takes a starting point: its values become answers, and the ones that
// mean something right now take effect before the next page is drawn. The
// console keyboard is loaded, because what is typed next is typed on it, and
// where the module tied the interface's own words to one of its variables the
// next frame is already read in that language.
func (a *app) adopt(o *spec.PresetOption) tea.Cmd {
	a.store.Apply(o)
	a.runner.Settle()
	if _, ok := o.Values[a.module.Language]; ok {
		a.speakLike(a.store.Get(a.module.Language))
	}
	return a.save()
}

// hintEnd is what enter promises on a page nothing follows. Where the module
// says how this machine is put down, enter continues to the page that asks; where it
// does not, it is the end of the program, and otherwise is the word for that.
func (a *app) hintEnd(otherwise string) string {
	if a.leaves() {
		return labelHintContinue()
	}
	return otherwise
}

// save writes the answer file. A machine that cannot record its own answers
// would ask again from the top after any interruption, so failing to save is
// worth saying out loud rather than carrying on quietly.
func (a *app) save() tea.Cmd {
	if err := a.store.Save(); err != nil {
		logging.Error("%s", err)
		return flashBad(err.Error())
	}
	return nil
}

// The opening is one chain, and each link only knows the one after it: pick a
// language, pick a module, settle whatever that module wants settled before
// anything is typed, join a network, let it look at the machine, pick a
// starting point, answer what is still open — and from then on it is simply
// ready. A link with nothing to ask hands straight on, so a module with no
// presets never shows a page offering none.
//
// The language leads because every word of every page after it is in it, the
// question of which module included — and because it is the runtime's own
// answer rather than any module's, the one thing settled before there is a
// module to settle anything. Which module comes next because everything after
// that belongs to it: the questions, the answers on disk, the work.

func (a *app) start() screen {
	// A forced run joins the chain where the asking stops: the module was named
	// and is open, the language is settled, and every question it might have put
	// has an answer. What is left is the module's own look at this machine, and
	// then the work.
	if a.forced {
		return a.afterNetwork()
	}
	return a.language()
}

// language is where the words the rest of this is read in are settled. It is
// asked whether or not a module was named on the way in: the words it puts on
// screen are the runtime's, and they are read before anything else is.
func (a *app) language() screen {
	if len(a.langs) < 2 {
		return a.chooseModule()
	}
	// Pushed rather than replacing this page, so esc on the page after it comes
	// back here. Choosing a language is a decision like any other and should be
	// as easy to take back.
	return newLanguage(a, func() tea.Cmd { return push(a.chooseModule()) })
}

// chooseModule is which of the runtime's modules this run is. A module named on
// the command line is already open by now, and one module is no question at all.
func (a *app) chooseModule() screen {
	if a.module != nil {
		return a.upfront()
	}
	return newChoice(a, func() tea.Cmd { return push(a.upfront()) })
}

// upfront asks what the module marked `first`, one question to a page and none
// of them numbered: this is not a run of questions but the few that cannot wait
// for one. It calls itself until nothing is left, which is also what makes a
// second start skip straight past — the answers are already in the file.
func (a *app) upfront() screen {
	open := a.store.Upfront()
	if len(open) == 0 {
		return a.network()
	}
	return newField(a, open[0], func() tea.Cmd { return push(a.upfront()) }).opening()
}

// network is where a module that describes one gets the chance to join it,
// because every stage past this point downloads something.
func (a *app) network() screen {
	if radio := a.runner.Radio(); radio != nil {
		return newNetwork(a, radio)
	}
	return a.afterNetwork()
}

// afterNetwork is where the network screen hands over, whether it joined
// something or was told to carry on without. Then comes the module's own check
// that this machine can be worked on at all, where it declares one.
func (a *app) afterNetwork() screen {
	if a.module.Hook(spec.HookPreflight) == "" {
		return a.afterCheck()
	}
	return newCheck(a)
}

// afterCheck is the module's starting points, one page each and in the order
// they were declared. They are skipped on a machine that has answered before: a
// starting point is only a starting point once, and after that every value one
// filled in is an ordinary answer somebody may since have changed.
func (a *app) afterCheck() screen {
	if a.forced {
		return startInstall(a, 0)
	}
	return a.preset(0)
}

func (a *app) preset(next int) screen {
	if !a.first || next >= len(a.module.Presets) {
		return a.afterPreset()
	}
	return newPreset(a, a.module.Presets[next], func() tea.Cmd { return push(a.preset(next + 1)) })
}

// afterPreset is the fork the whole program turns on: a question still open
// means the wizard, and nothing open means this machine is ready to run.
// There is no flag recording that — a required value with no answer is what
// makes the program ask, and an answer is what makes it stop.
func (a *app) afterPreset() screen {
	if missing := a.store.Missing(); len(missing) > 0 {
		return newWizard(a).screen(missing[0])
	}
	return newHub(a)
}

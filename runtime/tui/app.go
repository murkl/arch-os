package tui

import (
	"fmt"
	"io/fs"

	"installer/internal/i18n"
	"installer/internal/logging"
	"installer/internal/runner"
	"installer/internal/spec"
	"installer/internal/store"

	tea "github.com/charmbracelet/bubbletea"
)

// Program is one tree, opened: the answers it keeps, the runner that joins the
// two, and the words it is read in.
//
// What it takes to open one — where the answer file and the log go, what this
// machine has already been told — is the caller's business rather than the
// interface's, so the interface is handed the finished thing.
type Program struct {
	Spec    *spec.Spec
	Store   *store.Store
	Runner  *runner.Runner
	Langs   []i18n.Lang
	Sources []fs.FS
}

// Open opens one tree, once it has been chosen. Nothing is opened before that:
// the answers, the log and the catalogs are all named after the tree they belong
// to, and opening two would be a machine writing files for a program nobody
// asked for.
type Open func(*spec.Spec) (*Program, error)

// app is what every screen shares: the tree, the answers, and the runner that
// joins them. Screens hold a pointer to it rather than to each other.
type app struct {
	// What this release is called and what it looks like, and the programs it
	// holds with the way one of them is opened. Several is a question the
	// interface puts before anything else; one is opened on the way in and never
	// mentioned.
	release *spec.Release
	trees   []*spec.Spec
	open    Open

	spec    *spec.Spec
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
}

// Run shows the splash and then the interface, and returns when the user
// leaves. One program for both, because the splash fades into the first page
// and a fade cannot cross a program boundary — the terminal would drop out of
// the alternate screen in between. Choosing which tree to open happens inside
// it for the same reason.
func Run(rel *spec.Release, trees []*spec.Spec, open Open, version string) error {
	// Which kind of terminal this is has to be settled here: the question is put
	// to the terminal itself, and from the next line on there is a key reader
	// running that would take the answer for somebody typing.
	Adapt()
	a := &app{release: rel, trees: trees, open: open, version: version}
	// The frame is dressed before there is a tree to dress it with, and stays
	// dressed that way afterwards: the wordmark and the colour are the release's,
	// which is what makes two programs read as one product.
	SetAccent(rel.Accent)
	// One program is no question: it is opened here, so the interface comes up on
	// its first page rather than on a list with a single row on it.
	if len(trees) == 1 {
		if err := a.enter(trees[0]); err != nil {
			return err
		}
	}
	if _, err := tea.NewProgram(newModel(a, rel.Logo), tea.WithAltScreen()).Run(); err != nil {
		return err
	}
	// After the program, not inside it: the alternate screen is gone by now, so
	// this lands on the terminal the user is left sitting at rather than on a
	// frame that is about to be wiped.
	if a.farewell != "" {
		fmt.Println(a.farewell)
	}
	return nil
}

// enter opens a tree and makes it the one this run is about: from here on the
// answers, the log and every word on screen belong to it.
//
// Choosing the tree already open is not a second opening. It would rotate a log
// this run is already writing, and there is nothing to settle that the first one
// did not.
func (a *app) enter(sp *spec.Spec) error {
	if a.spec == sp {
		return nil
	}
	p, err := a.open(sp)
	if err != nil {
		return err
	}
	a.spec, a.store, a.runner = p.Spec, p.Store, p.Runner
	a.langs, a.sources = p.Langs, p.Sources
	a.first = !p.Store.Exists()
	return nil
}

// brand is what the frame is titled: the tree this run is about, once one has
// been chosen. The page that asks which program to open is not any of them —
// titling it after one would answer its own question — so it wears the release's
// own name, and nothing at all where the release did not give one.
func (a *app) brand() string {
	if a.spec == nil {
		return a.release.Name
	}
	return a.spec.Name()
}

// leaves reports whether this machine has to be asked about on the way out. A
// program nobody has opened yet has said nothing about the machine, so leaving
// the page that asks which one is leaving.
func (a *app) leaves() bool { return a.spec != nil && a.spec.Leaves() }

// speak puts the whole interface in a language and remembers the choice like
// any other answer. Every word on screen is read through i18n at draw time, so
// there is nothing to rebuild — the next frame is simply in the new language.
func (a *app) speak(code string) tea.Cmd {
	i18n.Activate(code, a.sources...)
	a.store.Set(spec.LangVar, code)
	return a.save()
}

// speakLike puts the interface in whatever language an answer comes closest to,
// for the tree that ties one of its own variables to the words on screen — see
// `language:` in installer.yaml.
//
// A locale is not a catalog, so the match is by language rather than by name:
// de_AT is German. An answer no catalog fits leaves the source language
// standing, which is what an installer nobody has translated already is.
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
	a.store.Set(spec.LangVar, code)
}

// adopt takes a starting point: its values become answers, and the ones that
// mean something right now take effect before the next page is drawn. The
// console keyboard is loaded, because what is typed next is typed on it, and
// where the tree tied the interface's own words to one of its variables the
// next frame is already read in that language.
func (a *app) adopt(o *spec.PresetOption) tea.Cmd {
	a.store.Apply(o)
	a.runner.Settle()
	if _, ok := o.Values[a.spec.Language]; ok {
		a.speakLike(a.store.Get(a.spec.Language))
	}
	return a.save()
}

// hintEnd is what enter promises on a page nothing follows. Where the tree says
// how this machine is put down, enter continues to the page that asks; where it
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
// program, pick a language, settle whatever the tree wants settled before
// anything is typed, join a network, let the tree look at the machine, pick a
// starting point, answer what is still open — and from then on the installer is
// simply ready. A link with nothing to ask hands straight on, so a tree with no
// presets never shows a page offering none.
//
// Which program leads because everything after it belongs to it — the questions,
// the answers on disk, the words on screen. The language comes next because
// every word of every page after that is in it, and because the first thing
// typed on this machine can already be the wrong thing: a wireless passphrase
// given on a keyboard nobody chose is not the passphrase.

func (a *app) start() screen {
	if a.spec == nil {
		return newChoice(a, func() tea.Cmd { return push(a.language()) })
	}
	return a.language()
}

// language is where the words the rest of this is read in are settled.
func (a *app) language() screen {
	// A tree that ties the interface to one of its own answers has already asked
	// which language this is by asking that question, and a page of nothing but
	// languages in front of it would ask the same thing twice.
	if a.first && a.spec.Language == "" && len(a.langs) > 1 {
		// Pushed rather than replacing this page, so esc on the page after it
		// comes back here. Choosing a language is a decision like any other and
		// should be as easy to take back.
		return newLanguage(a, func() tea.Cmd { return push(a.afterLanguage()) })
	}
	return a.afterLanguage()
}

// afterLanguage asks what the tree marked `first`, one question to a page and
// none of them numbered: this is not a run of questions but the few that cannot
// wait for one. It calls itself until nothing is left, which is also what makes
// a second start skip straight past — the answers are already in the file.
func (a *app) afterLanguage() screen {
	open := a.store.Upfront()
	if len(open) == 0 {
		return a.network()
	}
	return newField(a, open[0], func() tea.Cmd { return push(a.afterLanguage()) }).opening()
}

// network is where a tree that describes one gets the chance to join it, because
// every stage past this point downloads something.
func (a *app) network() screen {
	if radio := a.runner.Radio(); radio != nil {
		return newNetwork(a, radio)
	}
	return a.afterNetwork()
}

// afterNetwork is where the network screen hands over, whether it joined
// something or was told to carry on without. Then comes the tree's own check
// that this machine can be installed onto at all, where it declares one.
func (a *app) afterNetwork() screen {
	if a.spec.Hook(spec.HookPreflight) == "" {
		return a.afterCheck()
	}
	return newCheck(a)
}

// afterCheck is the tree's starting points, one page each and in the order they
// were declared. They are skipped on a machine that has answered before: a
// starting point is only a starting point once, and after that every value one
// filled in is an ordinary answer somebody may since have changed.
func (a *app) afterCheck() screen { return a.preset(0) }

func (a *app) preset(next int) screen {
	if !a.first || next >= len(a.spec.Presets) {
		return a.afterPreset()
	}
	return newPreset(a, a.spec.Presets[next], func() tea.Cmd { return push(a.preset(next + 1)) })
}

// afterPreset is the fork the whole program turns on: a question still open
// means the wizard, and nothing open means this machine is ready to install.
// There is no flag recording that — a required value with no answer is what
// makes the program ask, and an answer is what makes it stop.
func (a *app) afterPreset() screen {
	if missing := a.store.Missing(); len(missing) > 0 {
		return newWizard(a).screen(missing[0])
	}
	return newHub(a)
}

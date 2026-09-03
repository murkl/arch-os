// Package runner joins the module to the answers: what a question offers right
// now, which tasks this run consists of, and how one of them is started.
//
// It is the only thing above the shell layer that starts anything, and the only
// thing below the interface that knows what a task is. The interface asks it
// questions and draws the answers; it never reaches for a process itself.
package runner

import (
	osexec "os/exec"
	"strings"

	"github.com/murkl/arch-os/runtime/internal/exec"
	"github.com/murkl/arch-os/runtime/internal/i18n"
	"github.com/murkl/arch-os/runtime/internal/logging"
	"github.com/murkl/arch-os/runtime/internal/spec"
	"github.com/murkl/arch-os/runtime/internal/store"
	"github.com/murkl/arch-os/runtime/internal/wlan"
)

type Runner struct {
	mod   *spec.Module
	store *store.Store
	sh    exec.Runner
	radio *wlan.Radio
}

func New(mod *spec.Module, st *store.Store) *Runner {
	sh := exec.Runner{Lib: mod.Lib}
	cfg := wlan.Config{
		Online:   spec.Source(mod.Hook(spec.HookOnline)),
		Device:   spec.Source(mod.Hook(spec.HookDevice)),
		Networks: spec.Source(mod.Hook(spec.HookNetworks)),
		Connect:  spec.Source(mod.Hook(spec.HookConnect)),
	}
	return &Runner{mod: mod, store: st, sh: sh, radio: wlan.New(cfg, sh, st.Env)}
}

// Radio is how this module finds and joins a wireless network, or nil when it
// declares none.
func (r *Runner) Radio() *wlan.Radio { return r.radio }

// Option is one answer a question offers: the value that gets stored, and the
// text it is chosen by.
//
// They are usually the same word, and for a written-out set they always are.
// They part company where the value is a name nobody can pick between on its
// own — a disk is /dev/nvme0n1, and what tells it apart from the other one is
// its size and its model. A command may hand back both by putting a tab
// between them: everything before the tab is stored, everything after it is
// read. One rule, one character, and nothing to declare.
type Option struct {
	Value string
	Label string
}

// Options is the set of answers a question offers, in the order it offers them.
// Nil means there is no set and the answer is typed.
//
// A bool answers itself — the two values are the runtime's, not the folder's,
// because what they mean is the runtime's business: they are what a script
// tests against, and what they are called is a word in the interface's own
// language rather than anything a folder should have to translate.
func (r *Runner) Options(v *spec.Variable) ([]Option, error) {
	switch {
	case v.Shape() == spec.TypeBool:
		return []Option{
			{Value: spec.BoolTrue, Label: store.Label(spec.BoolTrue)},
			{Value: spec.BoolFalse, Label: store.Label(spec.BoolFalse)},
		}, nil
	case len(v.Values) > 0:
		out := make([]Option, len(v.Values))
		for i, value := range v.Values {
			out[i] = Option{Value: value, Label: store.Label(value)}
		}
		return out, nil
	case v.Command != "":
		lines, err := r.sh.Lines(v.Command, r.store.Env())
		if err != nil {
			logging.Warn("options for %s: %s", v.Name, err)
			return nil, err
		}
		out := make([]Option, 0, len(lines))
		for _, line := range lines {
			value, label, tabbed := strings.Cut(line, "\t")
			value = strings.TrimSpace(value)
			if !tabbed {
				label = value
			}
			out = append(out, Option{Value: value, Label: strings.TrimSpace(label)})
		}
		return out, nil
	}
	return nil, nil
}

// Prefill is the value a question opens on when nothing has answered it yet — a
// timezone guessed from the network, a keymap read off the live system. Only
// ever a suggestion, and a command that fails or says nothing simply leaves the
// question empty, because a suggestion is never worth stopping for.
func (r *Runner) Prefill(v *spec.Variable) string {
	if v.Prefill == "" {
		return ""
	}
	out, err := r.sh.Run(v.Prefill, r.store.Env())
	if err != nil {
		logging.Warn("prefill for %s: %s", v.Name, err)
		return ""
	}
	return out
}

// Apply puts an answer into effect on the machine the installer is running on,
// rather than on the one being installed — the console keyboard, which is
// unusable as a stored string and has to be loaded before the next thing is
// typed.
//
// A failure is a warning and no more, like a prefill's: the answer stands
// either way, and an installer that stops because a keymap would not load is
// worse than one carrying on with the layout it already had.
func (r *Runner) Apply(v *spec.Variable) {
	if v.Apply == "" {
		return
	}
	if _, err := r.sh.Run(v.Apply, r.store.Env()); err != nil {
		logging.Warn("apply for %s: %s", v.Name, err)
	}
}

// Import is shell that answers questions rather than reporting anything: a
// configuration fetched from wherever somebody shared it, merged into the
// answer file. What comes back is what it said if it would not work, which is a
// sentence for the page that asked rather than a report of a broken task.
//
// It is handed back as something to run rather than run here, because it talks
// to the network and the frame has to keep drawing while it does. The
// environment is taken now, on the goroutine that owns the answers; the shell
// itself may run anywhere. Reading back what it wrote is Imported, which
// belongs on this side again.
func (r *Runner) Import(shell string) func() error {
	env := r.store.Env()
	return func() error { return r.sh.Reason(shell, env) }
}

// Imported reads back what such a script left in the answer file and puts
// whatever it answered into force — the console keyboard, most of all, since
// what is typed next is typed on it.
func (r *Runner) Imported() error {
	// Load again over what is held. The answer file is the channel because it
	// already is one: shell, KEY='value' to a line, and somebody editing it in
	// an editor is doing exactly what such a script does — so there is no second
	// way in for a script to learn and no second way for one to go wrong.
	if err := r.store.Load(); err != nil {
		return err
	}
	r.Settle()
	return nil
}

// Settle applies every answer that stands, so the live system agrees with the
// answer file: at startup, so a second start stands where the first one left
// off, and after a preset, whose values were never typed at a prompt that could
// have applied them one at a time.
func (r *Runner) Settle() {
	for _, v := range r.mod.Vars {
		if r.store.Get(v.Name) != "" {
			r.Apply(v)
		}
	}
}

// Tasks is what this run consists of: the ones belonging to the mode this run
// is in and whose conditions hold, in the order the module put them in. One that
// has ruled itself out is not listed at all — the list is a promise of what is
// about to happen, and a row that will be skipped is not part of that promise.
func (r *Runner) Tasks() []*spec.Task {
	var out []*spec.Task
	for _, t := range r.mod.Tasks {
		if t.Applies(r.store.Get) {
			out = append(out, t)
		}
	}
	return out
}

// Start runs one task in the background. Its output goes to the log and
// nowhere else; what comes back here is whether it worked.
func (r *Runner) Start(t *spec.Task) (*exec.Session, error) {
	logging.Info("%s", t.Name)
	return r.sh.Start(t.Label(), t.Path(), r.store.Env())
}

// Terminal is a task that takes the terminal over, built but not started —
// the interface has to stand aside first, and only it knows how.
func (r *Runner) Terminal(t *spec.Task) *osexec.Cmd {
	logging.Info("%s", t.Name)
	return r.sh.Terminal(t.Path(), r.store.Env())
}

// Leave carries out one of the two ways this module says a machine is put down,
// and blocks until it has. What comes back is whether the hook worked — which
// on a machine that is genuinely restarting is a question nothing lives long
// enough to ask, and on one that is not is the only thing worth knowing.
//
// A module with no such hook has nothing to carry out and says so, so the
// interface never offers a row that would do nothing.
func (r *Runner) Leave(restart bool) error {
	name := spec.HookShutdown
	if restart {
		name = spec.HookRestart
	}
	path := r.mod.Hook(name)
	if path == "" {
		return nil
	}
	logging.Info("leaving: %s", name)
	_, err := r.sh.Run(spec.Source(path), r.store.Env())
	return err
}

// Preflight runs the module's own check that this machine can be installed onto
// at all, and blocks until it has an answer. A module without the hook passes.
//
// It runs before anything is asked bar the few questions a module marks `first`,
// which is the whole point: being told the firmware is wrong is worth very
// little after twenty questions.
func (r *Runner) Preflight() error {
	path := r.mod.Hook(spec.HookPreflight)
	if path == "" {
		return nil
	}
	session, err := r.sh.Start(i18n.T("System check"), path, r.store.Env())
	if err != nil {
		return err
	}
	<-session.Done()
	return session.Err()
}

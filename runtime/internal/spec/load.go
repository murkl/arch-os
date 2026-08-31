package spec

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"installer/internal/i18n"

	"gopkg.in/yaml.v3"
)

// Find locates the tree this binary is the runtime for: the installer.yaml
// beside the binary itself, or wherever a caller points.
//
// Beside the binary and nowhere else, because that is what makes a release one
// thing — a folder holding the program and everything it runs, copied to a
// stick and started. A binary on its own is not an installer and never pretends
// to be one: finding nothing is an error with somewhere to look in it, not a
// program that starts up empty.
func Find(explicit string) (string, error) {
	look := func(dir string) (string, bool) {
		if dir == "" {
			return "", false
		}
		abs, err := filepath.Abs(dir)
		if err != nil {
			return "", false
		}
		if _, err := os.Stat(filepath.Join(abs, FileInstaller)); err != nil {
			return abs, false
		}
		return abs, true
	}
	if explicit != "" {
		if dir, ok := look(explicit); ok {
			return dir, nil
		}
		return "", fmt.Errorf("%s: %s", i18n.T("no installer here"), explicit)
	}
	beside, ok := look(binaryDir())
	if ok {
		return beside, nil
	}
	return "", fmt.Errorf("%s\n%s",
		i18n.T("No installer found."),
		i18n.T("%s has to sit next to this program, in %s.", FileInstaller, beside))
}

// binaryDir is where this program's own file is, with symlinks resolved so that
// a link on the path still finds the tree the binary was installed with.
func binaryDir() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
		exe = resolved
	}
	return filepath.Dir(exe)
}

// installerFile is installer.yaml as it is written: flat, because every key in
// it is about the installer as a whole and a nesting level would only be there
// to be typed.
type installerFile struct {
	Title    string `yaml:"title"`
	Logo     string `yaml:"logo"`
	Accent   string `yaml:"accent"`
	Console  string `yaml:"console"`
	Language string `yaml:"language"`

	// What this installer does. A tree that does one thing writes its stages and
	// its warning here and never says the word mode; one that does several names
	// them under `modes:` and leaves these two out. Both at once is refused —
	// see settleModes.
	Confirm string   `yaml:"confirm"`
	Stages  []string `yaml:"stages"`
	Modes   []*Mode  `yaml:"modes"`

	Presets   []*Preset   `yaml:"presets"`
	Variables []*Variable `yaml:"variables"`
}

// Load reads a tree into a Spec and checks it over — every reference resolved,
// every script found, every condition naming a variable that exists, every task
// in a stage that exists and in an order that can be walked.
//
// A tree that loads is a tree that runs: an authoring mistake is a message at
// startup, never a task that silently never fires.
func Load(dir string) (*Spec, error) {
	s := &Spec{Dir: dir, byName: map[string]*Variable{}}

	var head installerFile
	if err := read(filepath.Join(dir, FileInstaller), &head); err != nil {
		return nil, err
	}
	s.UI = UI{Title: head.Title, Logo: head.Logo, Accent: head.Accent, Console: head.Console}
	s.Presets, s.Vars, s.Language = head.Presets, head.Variables, head.Language
	if err := s.settleModes(&head); err != nil {
		return nil, err
	}
	s.Lib = beside(dir, FileLib)
	s.Locales = beside(dir, DirLocales)

	hooks, err := loadHooks(dir)
	if err != nil {
		return nil, err
	}
	s.hooks = hooks

	tasks, err := loadTasks(dir)
	if err != nil {
		return nil, err
	}
	if err := s.check(tasks); err != nil {
		return nil, err
	}
	return s, nil
}

// settleModes works out what this tree can do, so that everything below here
// reads one list of modes and never asks whether there were any.
//
// A tree that does one thing writes `stages:` and `confirm:` at the top level
// and gets a single nameless mode holding them — it is never asked which mode
// it is in, and nothing about the idea reaches it. A tree that does several
// names them, and then those two keys belong to a mode rather than to the
// installer: having them in both places would be two answers to one question,
// so it is refused rather than resolved.
func (s *Spec) settleModes(head *installerFile) error {
	where := FileInstaller + ": "
	if len(head.Modes) == 0 {
		if len(head.Stages) == 0 {
			return fmt.Errorf("%sno stages", where)
		}
		s.Modes = []*Mode{{Confirm: head.Confirm, Stages: head.Stages}}
		s.Stages = head.Stages
		return nil
	}
	if len(head.Stages) > 0 || head.Confirm != "" {
		return fmt.Errorf("%sstages and confirm belong to a mode once there are modes", where)
	}
	seen := map[string]bool{}
	owner := map[string]string{}
	for _, m := range head.Modes {
		switch {
		case m.ID == "":
			return fmt.Errorf("%sa mode needs an id", where)
		case seen[m.ID]:
			return fmt.Errorf("%smode %s is declared twice", where, m.ID)
		case m.Title == "":
			return fmt.Errorf("%smode %s: title is required", where, m.ID)
		case len(m.Stages) == 0:
			return fmt.Errorf("%smode %s: no stages", where, m.ID)
		}
		seen[m.ID] = true
		// A stage is what a task points at to say where it belongs, so it can
		// only belong to one mode — otherwise a task would be in two runs at
		// once and there would be nothing to read that says which.
		for _, stage := range m.Stages {
			if other, taken := owner[stage]; taken {
				return fmt.Errorf("%smode %s: stage %s already belongs to mode %s", where, m.ID, stage, other)
			}
			owner[stage] = m.ID
			s.Stages = append(s.Stages, stage)
		}
	}
	s.Modes = head.Modes
	return nil
}

// beside is the path of one of the tree's optional parts, or empty where the
// tree does not have it. Nothing declares them: being there is the declaration.
func beside(dir, name string) string {
	path := filepath.Join(dir, name)
	if _, err := os.Stat(path); err != nil {
		return ""
	}
	return path
}

// loadHooks reads hooks/, where every file is one of HookNames with .sh after
// it. Anything else there is refused rather than ignored: a hook nothing calls
// because its name has a typo in it would leave everything loading and nothing
// happening.
func loadHooks(dir string) (map[string]string, error) {
	base := filepath.Join(dir, DirHooks)
	entries, err := os.ReadDir(base)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	known := map[string]bool{}
	for _, name := range HookNames {
		known[name] = true
	}
	out := map[string]string{}
	for _, entry := range entries {
		name := strings.TrimSuffix(entry.Name(), ScriptExt)
		if entry.IsDir() || !known[name] || name == entry.Name() {
			return nil, fmt.Errorf("%s/%s: not a hook — one of %s with %s after it",
				DirHooks, entry.Name(), strings.Join(HookNames, ", "), ScriptExt)
		}
		out[name] = filepath.Join(base, entry.Name())
	}
	return out, nil
}

// loadTasks reads every tasks/<id>/task.yaml, in folder order.
//
// A subfolder without one is an authoring mistake rather than an opt-out: it is
// an error, not a unit quietly dropped from the installation.
func loadTasks(dir string) ([]*Task, error) {
	base := filepath.Join(dir, DirTasks)
	entries, err := os.ReadDir(base)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("no %s folder in %s", DirTasks, dir)
		}
		return nil, err
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].Name() < entries[j].Name() })

	var out []*Task
	for _, entry := range entries {
		id := entry.Name()
		if !entry.IsDir() {
			continue
		}
		where := filepath.Join(base, id)
		t := &Task{id: id, path: filepath.Join(where, FileScript)}
		if err := read(filepath.Join(where, FileTask), t); err != nil {
			return nil, err
		}
		if _, err := os.Stat(t.path); err != nil {
			return nil, fmt.Errorf("%s/%s: missing %s", DirTasks, id, FileScript)
		}
		out = append(out, t)
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("%s: no tasks", DirTasks)
	}
	return out, nil
}

// read decodes one file with unknown keys refused. A misspelled key that is
// merely ignored is the worst kind of authoring bug: everything loads, nothing
// behaves, and there is nothing to look at.
func read(path string, into any) error {
	raw, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	dec := yaml.NewDecoder(bytes.NewReader(raw))
	dec.KnownFields(true)
	if err := dec.Decode(into); err != nil {
		return fmt.Errorf("%s: %w", filepath.Base(path), err)
	}
	return nil
}

func (s *Spec) check(tasks []*Task) error {
	s.normalize(tasks)
	if s.UI.Title == "" {
		return fmt.Errorf("%s: title is required", FileInstaller)
	}
	if s.UI.Accent != "" && !hexColor.MatchString(s.UI.Accent) {
		return fmt.Errorf("%s: accent must be #rrggbb, got %q", FileInstaller, s.UI.Accent)
	}
	if err := s.checkVars(); err != nil {
		return fmt.Errorf("%s: %w", FileInstaller, err)
	}
	if err := s.checkPresets(); err != nil {
		return fmt.Errorf("%s: %w", FileInstaller, err)
	}
	return s.checkTasks(tasks)
}

// checkTasks settles what runs and in what order: every task has to belong to a
// stage, and what is left is sorted once and for all.
func (s *Spec) checkTasks(tasks []*Task) error {
	// Which mode a stage puts a task in. Built here rather than carried on the
	// task, so a unit says where it belongs exactly once.
	mode := map[string]string{}
	for _, m := range s.Modes {
		for _, stage := range m.Stages {
			mode[stage] = m.ID
		}
	}
	for _, t := range tasks {
		where := DirTasks + "/" + t.id
		if t.Name == "" {
			return fmt.Errorf("%s: name is required", where)
		}
		if t.Stage == "" {
			return fmt.Errorf("%s: stage is required", where)
		}
		t.mode = mode[t.Stage]
		if err := s.checkAsks(t); err != nil {
			return fmt.Errorf("%s: %w", where, err)
		}
		if err := checkConfirm(t); err != nil {
			return fmt.Errorf("%s: %w", where, err)
		}
		cond, err := s.conditions(t.Conditions)
		if err != nil {
			return fmt.Errorf("%s: %w", where, err)
		}
		t.cond = cond
	}
	ordered, err := order(tasks, s.Stages)
	if err != nil {
		return fmt.Errorf("%s: %w", DirTasks, err)
	}
	s.Tasks = ordered
	return nil
}

// checkConfirm settles a task's `default:`, which says which of the two answers
// its offer opens on. There are exactly two, and a task that names one without
// making an offer at all has said something that can never take effect.
func checkConfirm(t *Task) error {
	switch {
	case t.Default == "":
		return nil
	case !t.Confirms():
		return fmt.Errorf("default: there is no confirm for it to answer")
	case t.Default != ConfirmYes && t.Default != ConfirmNo:
		return fmt.Errorf("default: %s or %s, got %q", ConfirmYes, ConfirmNo, t.Default)
	}
	return nil
}

// checkAsks settles a task's `asks:`, which is a question put in the middle of
// a run and therefore has to be one the frame can put there.
//
// Only a list qualifies. A text box mid-run would be a second way of answering
// with nothing to check it against on a page nobody navigated to, and a secret
// is already asked for at the one moment it is safe to — immediately before the
// run that needs it.
func (s *Spec) checkAsks(t *Task) error {
	if t.Asks == "" {
		return nil
	}
	v := s.byName[t.Asks]
	switch {
	case v == nil:
		return fmt.Errorf("asks: no such variable: %s", t.Asks)
	case v.Secret():
		return fmt.Errorf("asks: %s is a secret, which is asked for immediately before the run", t.Asks)
	case len(v.Values) == 0 && v.Command == "" && v.Shape() != TypeBool:
		return fmt.Errorf("asks: %s has no answers to choose from, and a question asked mid-run is a list", t.Asks)
	}
	v.deferred = true
	return nil
}

// normalize settles every word the tree says into the shape it is both shown in
// and translated by.
//
// Where a line ends in the yaml is not where it ends on screen: a description is
// written in a block scalar and wrapped by whoever was editing it, to whatever
// width their editor was that day. Those breaks are undone here, once, so that
// the text and the key a catalog looks it up by are the same string — and so a
// translator is handed one line per message instead of somebody's line wrapping
// to reproduce.
//
// A blank line survives, because that is the one break that was meant.
func (s *Spec) normalize(tasks []*Task) {
	fields := []*string{&s.UI.Title, &s.UI.Console}
	for _, m := range s.Modes {
		fields = append(fields, &m.Title, &m.Description, &m.Confirm)
	}
	for _, p := range s.Presets {
		fields = append(fields, &p.Title, &p.Description)
	}
	for _, v := range s.Vars {
		fields = append(fields, &v.Title, &v.Description, &v.Group, &v.Free, &v.Error)
	}
	for _, t := range tasks {
		fields = append(fields, &t.Name, &t.Confirm)
	}
	for _, f := range fields {
		*f = reflow(*f)
	}
}

// reflow joins the lines of each paragraph and keeps the blank lines between
// them.
func reflow(s string) string {
	paras := strings.Split(s, "\n\n")
	out := make([]string, 0, len(paras))
	for _, p := range paras {
		if p = strings.Join(strings.Fields(p), " "); p != "" {
			out = append(out, p)
		}
	}
	return strings.Join(out, "\n\n")
}

var (
	hexColor = regexp.MustCompile(`^#[0-9a-fA-F]{6}$`)
	varName  = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)
)

func (s *Spec) checkVars() error {
	for _, v := range s.Vars {
		switch {
		case !varName.MatchString(v.Name):
			return fmt.Errorf("%q is not a usable variable name", v.Name)
		case runtimeVar(v.Name):
			return fmt.Errorf("%s belongs to the runtime and cannot be declared", v.Name)
		case s.byName[v.Name] != nil:
			return fmt.Errorf("%s is declared twice", v.Name)
		case v.Title == "":
			return fmt.Errorf("%s: title is required", v.Name)
		}
		switch v.Shape() {
		case TypeText:
		case TypeBool, TypeSecret:
			if len(v.Values) > 0 || v.Command != "" {
				return fmt.Errorf("%s: a %s variable has no values of its own", v.Name, v.Shape())
			}
		default:
			return fmt.Errorf("%s: unknown type %q", v.Name, v.Type)
		}
		if v.Secret() && v.Default != "" {
			return fmt.Errorf("%s: a secret is never stored, so it cannot have a default", v.Name)
		}
		if v.Secret() && v.First {
			return fmt.Errorf("%s: a secret is asked for immediately before the run that needs it, so it cannot also be asked first", v.Name)
		}
		if v.Blind && !v.First {
			return fmt.Errorf("%s: blind only matters for a question asked first — anything later is typed on a keyboard already loaded", v.Name)
		}
		if err := s.belongs(v.Mode); err != nil {
			return fmt.Errorf("%s: %w", v.Name, err)
		}
		// A question asked before the mode is chosen cannot belong to one of
		// them: there is no answer yet to say which.
		if v.First && v.Mode != "" {
			return fmt.Errorf("%s: asked first, which is before there is a mode for it to belong to", v.Name)
		}
		if len(v.Values) > 0 && v.Command != "" {
			return fmt.Errorf("%s: values and command are two answers to the same question", v.Name)
		}
		if v.Pattern != "" {
			re, err := regexp.Compile(v.Pattern)
			if err != nil {
				return fmt.Errorf("%s: pattern: %w", v.Name, err)
			}
			v.re = re
		}
		for _, expr := range []*string{&v.Command, &v.Prefill, &v.Apply} {
			resolved, err := s.shell(*expr)
			if err != nil {
				return fmt.Errorf("%s: %w", v.Name, err)
			}
			*expr = resolved
		}
		s.byName[v.Name] = v
	}
	if s.Language != "" && s.byName[s.Language] == nil {
		return fmt.Errorf("language: no such variable: %s", s.Language)
	}
	// Conditions are checked once every name is known, so a variable may be
	// guarded by one declared after it.
	for _, v := range s.Vars {
		cond, err := s.conditions(v.Conditions)
		if err != nil {
			return fmt.Errorf("%s: %w", v.Name, err)
		}
		v.cond = cond
	}
	return nil
}

func (s *Spec) checkPresets() error {
	seen := map[string]bool{}
	for _, p := range s.Presets {
		switch {
		case p.ID == "":
			return fmt.Errorf("a preset needs an id")
		case seen[p.ID]:
			return fmt.Errorf("preset %s is declared twice", p.ID)
		case p.Title == "":
			return fmt.Errorf("preset %s: title is required", p.ID)
		case len(p.Options) == 0:
			// A page with nothing on it to choose would be a page nobody can
			// get past, which is an authoring mistake rather than a way of
			// turning the page off: leaving the whole preset out is that.
			return fmt.Errorf("preset %s: no options", p.ID)
		}
		seen[p.ID] = true
		if err := s.belongs(p.Mode); err != nil {
			return fmt.Errorf("preset %s: %w", p.ID, err)
		}
		chosen := map[string]bool{}
		for _, o := range p.Options {
			switch {
			case o.ID == "":
				return fmt.Errorf("preset %s: an option needs an id", p.ID)
			case chosen[o.ID]:
				return fmt.Errorf("preset %s: option %s is declared twice", p.ID, o.ID)
			case o.Title == "":
				return fmt.Errorf("preset %s: option %s: title is required", p.ID, o.ID)
			}
			chosen[o.ID] = true
			for name := range o.Values {
				if s.byName[name] == nil {
					return fmt.Errorf("preset %s: option %s: no such variable: %s", p.ID, o.ID, name)
				}
			}
		}
	}
	return nil
}

// conditions parses a `conditions:` and checks that every line of it is about a
// variable this tree actually declares.
//
// Which mode a row belongs to is deliberately not one of them: that is `mode:`,
// a key of its own, because there is nothing to compare. A row is one mode's or
// it is everybody's, and two ways of writing the same guard would be one too
// many.
func (s *Spec) conditions(exprs Conditions) ([]*condition, error) {
	var out []*condition
	for _, expr := range exprs {
		if strings.TrimSpace(expr) == "" {
			continue
		}
		c, err := parseCondition(expr)
		if err != nil {
			return nil, err
		}
		if s.byName[c.name] == nil {
			return nil, fmt.Errorf("conditions: no such variable: %s", c.name)
		}
		out = append(out, c)
	}
	return out, nil
}

// belongs checks that a `mode:` names a mode this tree offers. A row guarded by
// one that does not exist is a row that never appears, which is exactly the
// silence every check here exists to prevent.
func (s *Spec) belongs(mode string) error {
	if mode == "" || s.Mode(mode) != nil {
		return nil
	}
	return fmt.Errorf("no such mode: %s", mode)
}

// shell settles a field that may hold either shell or the file it lives in: a
// single line beginning with ./ or ../ names a file, anything else is the shell
// itself. So a one-line option list stays in the yaml where it is read together
// with the variable, and a long one moves into a file beside it — without a
// second notation to learn.
func (s *Spec) shell(expr string) (string, error) {
	trimmed := strings.TrimSpace(expr)
	if trimmed == "" || strings.Contains(trimmed, "\n") {
		return expr, nil
	}
	if !strings.HasPrefix(trimmed, "./") && !strings.HasPrefix(trimmed, "../") {
		return expr, nil
	}
	path := filepath.Join(s.Dir, trimmed)
	if _, err := os.Stat(path); err != nil {
		return "", fmt.Errorf("no such script: %s", trimmed)
	}
	return Source(path), nil
}

// quote wraps a path for the shell, so a tree whose name holds a space or a
// quote is still one word.
func quote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

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

// Trees lists the programs this binary can run, in the order it offers them:
// the folder named — beside the binary itself when none is — if that folder is
// a tree, and otherwise every folder inside it that is.
//
// A release is the binary and the trees beside it, a folder each, which is what
// makes it one thing: copied to a stick and started, it holds every program the
// machine it boots might need. Several of them is a question the runtime puts
// before anything else; one is no question at all.
//
// Beside the binary and nowhere else, because a binary on its own is not an
// installer and never pretends to be one: finding nothing is an error with
// somewhere to look in it, not a program that starts up empty.
//
// They are offered in folder order, so what a release is asked first is what its
// folders are called.
func Trees(explicit string) ([]string, error) {
	dir := explicit
	if dir == "" {
		dir = binaryDir()
	}
	dir, err := filepath.Abs(dir)
	if err != nil {
		return nil, err
	}
	// A folder holding a declaration is itself the tree, and there is nothing
	// below it to look at. Two declarations in it is refused here rather than
	// resolved, exactly as it is when a tree is named outright.
	if len(declarations(dir)) > 0 {
		if _, err := Declaration(dir); err != nil {
			return nil, fmt.Errorf("%s: %w", dir, err)
		}
		return []string{dir}, nil
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var out []string
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		if sub := filepath.Join(dir, entry.Name()); len(declarations(sub)) > 0 {
			if _, err := Declaration(sub); err != nil {
				return nil, fmt.Errorf("%s: %w", sub, err)
			}
			out = append(out, sub)
		}
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("%s\n%s",
			i18n.T("No installer found."),
			i18n.T("A %s file has to sit next to this program, in %s.", SpecExt, dir))
	}
	return out, nil
}

// Declaration is the tree's own yaml, by name: the one file ending in SpecExt
// in the folder's top level. The catalogs and the tasks are yaml too, which is
// why only the top level counts — everything below it belongs to a part of the
// tree that is found by its own name.
//
// Two of them is refused rather than resolved: a folder holding an
// installer.yaml and a recovery.yaml is two trees in one place, and picking one
// would be the runtime deciding which installer somebody meant.
func Declaration(dir string) (string, error) {
	switch found := declarations(dir); len(found) {
	case 1:
		return found[0], nil
	case 0:
		return "", fmt.Errorf("%s", i18n.T("no %s file here", SpecExt))
	default:
		return "", fmt.Errorf("%s: %s", i18n.T("more than one %s file here", SpecExt), strings.Join(found, ", "))
	}
}

// declarations is every top-level yaml in a folder, in name order. A folder
// that cannot be read holds none, which is what a caller about to read it again
// wants: the error belongs to whoever is looking, not to the counting.
func declarations(dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var found []string
	for _, entry := range entries {
		if !entry.IsDir() && strings.HasSuffix(entry.Name(), SpecExt) {
			found = append(found, entry.Name())
		}
	}
	return found
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

// declaration is the tree's yaml as it is written: flat, because every key in
// it is about the installer as a whole and a nesting level would only be there
// to be typed.
type declaration struct {
	Title    string `yaml:"title"`
	Logo     string `yaml:"logo"`
	Accent   string `yaml:"accent"`
	Console  string `yaml:"console"`
	Language string `yaml:"language"`

	// What this installer is and what it does: one sentence about the program,
	// the name of one run of it, the last warning before that run starts, and the
	// phases it happens in.
	Description string   `yaml:"description"`
	Run         string   `yaml:"run"`
	Confirm     string   `yaml:"confirm"`
	Stages      []string `yaml:"stages"`

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
	file, err := Declaration(dir)
	if err != nil {
		return nil, err
	}
	s := &Spec{Dir: dir, File: file, byName: map[string]*Variable{}}

	var head declaration
	if err := read(filepath.Join(dir, file), &head); err != nil {
		return nil, err
	}
	s.UI = UI{
		Title: head.Title, Logo: head.Logo, Accent: head.Accent, Console: head.Console,
		Description: head.Description, Run: head.Run,
	}
	s.Presets, s.Vars, s.Language = head.Presets, head.Variables, head.Language
	s.Confirm, s.Stages = head.Confirm, head.Stages
	if len(s.Stages) == 0 {
		return nil, fmt.Errorf("%s: no stages", s.File)
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
		return fmt.Errorf("%s: title is required", s.File)
	}
	if s.UI.Accent != "" && !hexColor.MatchString(s.UI.Accent) {
		return fmt.Errorf("%s: accent must be #rrggbb, got %q", s.File, s.UI.Accent)
	}
	if err := s.checkVars(); err != nil {
		return fmt.Errorf("%s: %w", s.File, err)
	}
	if err := s.checkPresets(); err != nil {
		return fmt.Errorf("%s: %w", s.File, err)
	}
	return s.checkTasks(tasks)
}

// checkTasks settles what runs and in what order: every task has to belong to a
// stage, and what is left is sorted once and for all.
func (s *Spec) checkTasks(tasks []*Task) error {
	for _, t := range tasks {
		where := DirTasks + "/" + t.id
		if t.Name == "" {
			return fmt.Errorf("%s: name is required", where)
		}
		if t.Stage == "" {
			return fmt.Errorf("%s: stage is required", where)
		}
		if err := s.checkAsks(t); err != nil {
			return fmt.Errorf("%s: %w", where, err)
		}
		if err := checkConfirm(t); err != nil {
			return fmt.Errorf("%s: %w", where, err)
		}
		if err := s.checkShows(t); err != nil {
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

// checkShows settles a task's `shows:`, which is an answer put on the page its
// `report:` draws — as a code to scan, and under it as itself.
//
// A secret is refused for the reason it is refused everywhere: it is never
// written down, and drawing one at a size a camera across the room can read is
// the opposite of what it is for.
func (s *Spec) checkShows(t *Task) error {
	if t.Shows == "" {
		return nil
	}
	v := s.byName[t.Shows]
	switch {
	case v == nil:
		return fmt.Errorf("shows: no such variable: %s", t.Shows)
	case v.Secret():
		return fmt.Errorf("shows: %s is a secret, and a secret is not put on screen to be read across a room", t.Shows)
	case !t.Reports():
		return fmt.Errorf("shows: there is no report for it to appear on")
	}
	v.deferred = true
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
	fields := []*string{&s.UI.Title, &s.UI.Description, &s.UI.Run, &s.UI.Console, &s.Confirm}
	for _, p := range s.Presets {
		fields = append(fields, &p.Title, &p.Description)
		for _, o := range p.Options {
			fields = append(fields, &o.Title, &o.Description)
		}
	}
	for _, v := range s.Vars {
		fields = append(fields, &v.Title, &v.Description, &v.Group, &v.Free, &v.Error)
	}
	for _, t := range tasks {
		fields = append(fields, &t.Name, &t.Confirm, &t.Report)
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
			if err := s.checkFetch(o); err != nil {
				return fmt.Errorf("preset %s: option %s: %w", p.ID, o.ID, err)
			}
		}
	}
	return nil
}

// checkFetch settles a preset option's `asks:` and `apply:` — the starting
// point that is fetched rather than written out here.
//
// The question is put on a page of its own, so unlike a task's it may be a text
// box: a code somebody was handed is typed, not chosen. A secret is refused,
// because a starting point is a set of answers and a secret is never one of
// them.
func (s *Spec) checkFetch(o *PresetOption) error {
	if o.Asks == "" {
		if o.Apply != "" {
			return fmt.Errorf("apply: there is no asks for it to work from")
		}
		return nil
	}
	v := s.byName[o.Asks]
	switch {
	case v == nil:
		return fmt.Errorf("asks: no such variable: %s", o.Asks)
	case v.Secret():
		return fmt.Errorf("asks: %s is a secret, which is asked for immediately before the run", o.Asks)
	}
	resolved, err := s.shell(o.Apply)
	if err != nil {
		return err
	}
	o.Apply = resolved
	v.deferred = true
	return nil
}

// conditions parses a `conditions:` and checks that every line of it is about a
// variable this tree actually declares.
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

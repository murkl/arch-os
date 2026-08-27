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
	Title     string      `yaml:"title"`
	Logo      string      `yaml:"logo"`
	Accent    string      `yaml:"accent"`
	Confirm   string      `yaml:"confirm"`
	Lib       string      `yaml:"lib"`
	Locales   string      `yaml:"locales"`
	Language  string      `yaml:"language"`
	Preflight string      `yaml:"preflight"`
	Wlan      *Wlan       `yaml:"wlan"`
	Leave     *Leave      `yaml:"leave"`
	Stages    []string    `yaml:"stages"`
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
	s.UI = UI{Title: head.Title, Logo: head.Logo, Accent: head.Accent, Confirm: head.Confirm}
	s.Presets, s.Vars, s.Stages = head.Presets, head.Variables, head.Stages
	s.Wlan, s.Leave, s.Language = head.Wlan, head.Leave, head.Language

	for path, into := range map[string]*string{head.Lib: &s.Lib, head.Locales: &s.Locales} {
		if path == "" {
			continue
		}
		abs := filepath.Join(dir, path)
		if _, err := os.Stat(abs); err != nil {
			return nil, fmt.Errorf("%s: no such file: %s", FileInstaller, path)
		}
		*into = abs
	}

	tasks, err := loadTasks(dir)
	if err != nil {
		return nil, err
	}
	if err := s.check(tasks, head.Preflight); err != nil {
		return nil, err
	}
	return s, nil
}

// loadTasks reads every tasks/<id>/task.yaml, in folder order.
//
// A subfolder without one is an authoring mistake rather than an opt-out: it is
// an error, not a unit quietly dropped from the installation. A folder whose
// name starts with _ is not a unit at all — that is where a tree keeps what its
// units share.
func loadTasks(dir string) ([]*Task, error) {
	base := filepath.Join(dir, TaskDir)
	entries, err := os.ReadDir(base)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("no %s folder in %s", TaskDir, dir)
		}
		return nil, err
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].Name() < entries[j].Name() })

	var out []*Task
	for _, entry := range entries {
		id := entry.Name()
		if !entry.IsDir() || strings.HasPrefix(id, SharedPrefix) {
			continue
		}
		where := filepath.Join(base, id)
		t := &Task{id: id, path: filepath.Join(where, TaskScript)}
		if err := read(filepath.Join(where, TaskFile), t); err != nil {
			return nil, err
		}
		if _, err := os.Stat(t.path); err != nil {
			return nil, fmt.Errorf("%s/%s: missing %s", TaskDir, id, TaskScript)
		}
		out = append(out, t)
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("%s: no tasks", TaskDir)
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

func (s *Spec) check(tasks []*Task, preflight string) error {
	s.normalize(tasks)
	if s.UI.Title == "" {
		return fmt.Errorf("%s: title is required", FileInstaller)
	}
	if s.UI.Accent != "" && !hexColor.MatchString(s.UI.Accent) {
		return fmt.Errorf("%s: accent must be #rrggbb, got %q", FileInstaller, s.UI.Accent)
	}
	if len(s.Stages) == 0 {
		return fmt.Errorf("%s: no stages", FileInstaller)
	}
	if err := s.checkVars(); err != nil {
		return fmt.Errorf("%s: %w", FileInstaller, err)
	}
	if err := s.checkPresets(); err != nil {
		return fmt.Errorf("%s: %w", FileInstaller, err)
	}
	if err := s.checkWlan(); err != nil {
		return fmt.Errorf("%s: %w", FileInstaller, err)
	}
	if err := s.checkLeave(); err != nil {
		return fmt.Errorf("%s: %w", FileInstaller, err)
	}
	return s.checkTasks(tasks, preflight)
}

// checkWlan validates the tree's optional network description: Check is the
// one thing it must declare, and every command may point at a file the same
// way a variable's command or prefill does.
func (s *Spec) checkWlan() error {
	if s.Wlan == nil {
		return nil
	}
	if s.Wlan.Check == "" {
		return fmt.Errorf("wlan: check is required")
	}
	for _, expr := range []*string{
		&s.Wlan.Check, &s.Wlan.Device, &s.Wlan.Scan, &s.Wlan.Networks, &s.Wlan.Connect,
	} {
		resolved, err := s.shell(*expr)
		if err != nil {
			return fmt.Errorf("wlan: %w", err)
		}
		*expr = resolved
	}
	return nil
}

// checkLeave validates the tree's optional way out. Declaring the block and
// naming nothing in it is an authoring mistake rather than a way to turn it off:
// it would trap the interface on a page with no rows on it. Each command may
// point at a file the same way a variable's command does.
func (s *Spec) checkLeave() error {
	if s.Leave == nil {
		return nil
	}
	for _, expr := range []*string{&s.Leave.Restart, &s.Leave.Shutdown} {
		resolved, err := s.shell(*expr)
		if err != nil {
			return fmt.Errorf("leave: %w", err)
		}
		*expr = resolved
	}
	if !s.Leave.Offers() {
		return fmt.Errorf("leave: restart, shutdown or console is required")
	}
	return nil
}

// checkTasks settles what runs and in what order: the one that runs before
// everything else is taken out, every other one has to belong to a stage, and
// what is left is sorted once and for all.
func (s *Spec) checkTasks(tasks []*Task, preflight string) error {
	if preflight != "" {
		named := false
		for _, t := range tasks {
			named = named || t.id == preflight
		}
		if !named {
			return fmt.Errorf("%s: preflight: no such task: %s", FileInstaller, preflight)
		}
	}

	staged := make([]*Task, 0, len(tasks))
	for _, t := range tasks {
		where := TaskDir + "/" + t.id
		if t.Name == "" {
			return fmt.Errorf("%s: name is required", where)
		}
		cond, err := s.conditions(t.Conditions)
		if err != nil {
			return fmt.Errorf("%s: %w", where, err)
		}
		t.cond = cond

		if t.id == preflight {
			if t.Stage != "" {
				return fmt.Errorf("%s: the preflight runs before every stage, so it belongs to none", where)
			}
			s.Preflight = t
			continue
		}
		if t.Stage == "" {
			return fmt.Errorf("%s: stage is required", where)
		}
		staged = append(staged, t)
	}
	ordered, err := order(staged, s.Stages)
	if err != nil {
		return fmt.Errorf("%s: %w", TaskDir, err)
	}
	s.Tasks = ordered
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
	fields := []*string{&s.UI.Title, &s.UI.Confirm}
	if s.Wlan != nil {
		fields = append(fields, &s.Wlan.Title, &s.Wlan.Description)
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
		case v.Name == LangVar:
			return fmt.Errorf("%s belongs to the runtime and cannot be declared", LangVar)
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
		}
	}
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
	return "source " + quote(path), nil
}

// quote wraps a path for the shell, so a tree whose name holds a space or a
// quote is still one word.
func quote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

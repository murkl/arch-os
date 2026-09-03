package cli

import (
	"strings"
	"testing"

	"github.com/murkl/arch-os/runtime/internal/spec"
)

// A command line the way a run has one: two flags of the runtime's that take a
// value, one switch, and the two a module declared.
func flags() []spec.Flag {
	return []spec.Flag{
		{Name: "conf", Value: "path", Title: "Where the answers are kept."},
		{Name: "dir", Value: "path", Title: "Where the modules are."},
		{Name: "force", Title: "Ask nothing."},
		{Name: "password", Value: "value", Title: "Password"},
		{Name: "debug", Title: "Simulate the run."},
	}
}

func read(t *testing.T, args ...string) *Command {
	t.Helper()
	c, err := Parse(args, flags())
	if err != nil {
		t.Fatalf("Parse(%v) = %v", args, err)
	}
	return c
}

// The one word on a command line that is not a flag is the module, with or
// without the dashes an option would carry, and wherever it stands.
func TestTheModuleIsTheOneWordNobodyDeclared(t *testing.T) {
	for _, tc := range []struct {
		name string
		args []string
		want string
		conf string
	}{
		{"as an option", []string{"--installer"}, "installer", ""},
		{"as a word", []string{"installer"}, "installer", ""},
		{"with one dash", []string{"-recovery"}, "recovery", ""},
		{"in front of the flags", []string{"--recovery", "--conf", "x"}, "recovery", "x"},
		{"behind them", []string{"--conf", "x", "installer"}, "installer", "x"},
		{"between them", []string{"--conf", "x", "--installer", "--force"}, "installer", "x"},
		{"nothing at all", nil, "", ""},
		{"a flag is not a module", []string{"--conf", "x"}, "", "x"},
		{"nor is its value", []string{"--conf", "installer"}, "", "installer"},
		{"nor is one with its value attached", []string{"--conf=x"}, "", "x"},
		{"a switch never eats the word behind it", []string{"--force", "installer"}, "installer", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := read(t, tc.args...)
			if got.Module != tc.want {
				t.Errorf("Parse(%v).Module = %q, want %q", tc.args, got.Module, tc.want)
			}
			if got.Value("conf") != tc.conf {
				t.Errorf("Parse(%v) conf = %q, want %q", tc.args, got.Value("conf"), tc.conf)
			}
		})
	}
}

// A module's own flags are read off the same line as the runtime's, and neither
// half knows which of them belongs to the other.
func TestAModulesFlagsAreReadLikeTheRuntimesOwn(t *testing.T) {
	c := read(t, "--installer", "--force", "--password=hunter2", "--debug")
	if c.Module != "installer" {
		t.Errorf("Module = %q, want installer", c.Module)
	}
	if !c.On("force") || !c.On("debug") {
		t.Error("a switch given on its own is not on")
	}
	if got := c.Value("password"); got != "hunter2" {
		t.Errorf("password = %q, want hunter2", got)
	}
}

// A switch says so by being there. It is written out only to say the opposite,
// which is what makes a default of true something a line can still turn off.
func TestASwitchIsOnByBeingThereAndOffOnlyByBeingSaidSo(t *testing.T) {
	if !read(t, "--debug").On("debug") {
		t.Error("--debug is not on")
	}
	if !read(t, "--debug=true").On("debug") {
		t.Error("--debug=true is not on")
	}
	c := read(t, "--debug=false")
	if c.On("debug") {
		t.Error("--debug=false is on")
	}
	if !c.Has("debug") {
		t.Error("--debug=false was not given at all, and it was")
	}
}

func TestACommandLineThatCannotBeReadSaysWhy(t *testing.T) {
	for _, tc := range []struct {
		name string
		args []string
		want string
	}{
		{"a value with nothing behind it", []string{"--conf"}, "takes a value"},
		{"a switch given a word of its own", []string{"--debug=maybe"}, "true or false"},
		{"two modules", []string{"installer", "recovery"}, "One module at a time"},
		{"an option nobody declared, after the module", []string{"--installer", "--passwrd=x"}, "No option called --passwrd"},
		{"a value set on a name nobody declared", []string{"--passwrd=x"}, "No option called --passwrd"},
		{"dashes with no name behind them", []string{"--"}, "names nothing"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Parse(tc.args, flags())
			if err == nil {
				t.Fatalf("Parse(%v) was read as sound", tc.args)
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Errorf("Parse(%v) = %q, want it to say %q", tc.args, err, tc.want)
			}
		})
	}
}

// An option nobody declared is only read as a module while there is no module.
// After that it is a mistake, and the message says what was on offer.
func TestAnUnknownOptionNamesWhatWasOnOffer(t *testing.T) {
	_, err := Parse([]string{"installer", "--nonsense"}, flags())
	if err == nil {
		t.Fatal("an option nobody declared was read as sound")
	}
	if !strings.Contains(err.Error(), "--password") {
		t.Errorf("error = %q, want it to list what a line may carry", err)
	}
}

// The first pass reads only what says where to look, and steps over everything
// else without touching the word behind it — it cannot know the shape of a flag
// no module has declared yet.
func TestTheEarlyPassReadsOnlyWhereToLook(t *testing.T) {
	own := []spec.Flag{{Name: "dir", Value: "path"}, {Name: "version"}}
	c := Early([]string{"--password", "hunter2", "--installer", "--dir", "/opt/arch-os"}, own)
	if got := c.Value("dir"); got != "/opt/arch-os" {
		t.Errorf("dir = %q, want /opt/arch-os", got)
	}
	if c.Module != "" {
		t.Errorf("Module = %q, want nothing — the early pass names no module", c.Module)
	}
	if c.On("version") {
		t.Error("--version is on, and it was never given")
	}
}

// Nothing is refused in the first pass: a line is judged once, in full, when
// everything it may carry is known.
func TestTheEarlyPassRefusesNothing(t *testing.T) {
	c := Early([]string{"--", "--nonsense=x", "-"}, []spec.Flag{{Name: "dir", Value: "path"}})
	if c.Has("dir") {
		t.Error("dir was read out of a line that never mentioned it")
	}
}

// Two modules may well want the same switch, and on a line that has not named
// one yet they are one flag. Two that disagree about whether it takes a value
// could not be read at all.
func TestTheSameFlagInTwoModulesIsOneFlag(t *testing.T) {
	a := []spec.Flag{{Name: "debug", Title: "Simulate the installation."}}
	b := []spec.Flag{{Name: "debug", Title: "Simulate the repair."}}
	got, err := Union(a, b)
	if err != nil {
		t.Fatalf("Union() = %v", err)
	}
	if len(got) != 1 || got[0].Name != "debug" {
		t.Errorf("Union() = %v, want one --debug", got)
	}
	if _, err := Union(a, []spec.Flag{{Name: "debug", Value: "value"}}); err == nil {
		t.Error("a flag that is a switch in one module and takes a value in another was allowed")
	}
}

// The runtime's flags and a module's are declared in places that cannot see
// each other, so the collision is found where the two meet.
func TestAModuleCannotTakeOverOneOfTheRuntimesFlags(t *testing.T) {
	own := []spec.Flag{{Name: "force"}, {Name: "conf", Value: "path"}}
	if got := Collide(own, []spec.Flag{{Name: "password", Value: "value"}}); got != "" {
		t.Errorf("Collide() = %q, want nothing", got)
	}
	if got := Collide(own, []spec.Flag{{Name: "force"}}); got != "force" {
		t.Errorf("Collide() = %q, want force", got)
	}
}

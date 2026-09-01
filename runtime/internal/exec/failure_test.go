package exec

import (
	"errors"
	"os/exec"
	"strings"
	"testing"
)

// A failure report is the most important text this program ever puts on screen,
// and the frame lays it out as a table — so what it holds is a contract.
func TestAFailureIsReportedAsLabelledFields(t *testing.T) {
	f := &Failure{
		Unit: "Set up the disk", Script: "/tree/tasks/disk/task.sh", Line: 12,
		Code: 2, Command: "mkfs.btrfs -f /dev/sda2", Stderr: "no such device",
	}
	got := f.Fields()
	want := [][2]string{
		{"Script", "/tree/tasks/disk/task.sh:12"},
		{"Command", "mkfs.btrfs -f /dev/sda2"},
		{"Exit code", "2"},
	}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("field %d = %v, want %v", i, got[i], want[i])
		}
	}

	msg := f.Error()
	for _, fragment := range []string{"Set up the disk failed", "task.sh:12", "mkfs.btrfs", "no such device"} {
		if !strings.Contains(msg, fragment) {
			t.Errorf("the message does not mention %q:\n%s", fragment, msg)
		}
	}
}

// A script that died without the trap having anything to say still reports the
// step and the exit code, and says nothing it does not know.
func TestAFailureWithNoTrapReportSaysOnlyWhatItKnows(t *testing.T) {
	f := &Failure{Unit: "Restart", Code: 1}
	got := f.Fields()
	if len(got) != 1 || got[0][0] != "Exit code" || got[0][1] != "1" {
		t.Fatalf("got %v, want the exit code alone", got)
	}
	if msg := f.Error(); msg != "Restart failed\nExit code:  1" {
		t.Errorf("the message is %q", msg)
	}
}

// Fail is for a script that was handed the terminal: what went wrong was on
// screen, so there is no trap report to fill in — only the code it left.
func TestFailCarriesTheExitCodeOfAScriptThatOwnedTheTerminal(t *testing.T) {
	if err := Fail("Enter the new system", nil); err != nil {
		t.Errorf("a script that worked reported %v", err)
	}

	cmd := exec.Command("sh", "-c", "exit 7")
	err := Fail("Enter the new system", cmd.Run())
	var f *Failure
	if !errors.As(err, &f) {
		t.Fatalf("got %T, want a *Failure", err)
	}
	if f.Unit != "Enter the new system" || f.Code != 7 {
		t.Errorf("got %q with code %d", f.Unit, f.Code)
	}
}

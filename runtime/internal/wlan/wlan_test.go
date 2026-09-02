package wlan

import (
	"strings"
	"testing"
	"time"

	"installer/internal/exec"
)

var sh = exec.Runner{}

func radio(cfg Config) *Radio {
	return &Radio{cfg: cfg, sh: sh, env: func() exec.Env { return nil }, settle: time.Millisecond, tries: 2}
}

func TestNewGivesNoRadioWhenTheTreeDescribesNone(t *testing.T) {
	if got := New(Config{}, sh, nil); got != nil {
		t.Errorf("New() = %v, want nil", got)
	}
}

func TestOnlineReportsWhatTheHookSays(t *testing.T) {
	if !radio(Config{Online: "true"}).Online() {
		t.Error("Online() = false, want true")
	}
	if radio(Config{Online: "false"}).Online() {
		t.Error("Online() = true, want false")
	}
}

func TestJoinableNeedsDeviceNetworksAndConnect(t *testing.T) {
	if radio(Config{Online: "true"}).Joinable() {
		t.Error("a tree with only an online hook reported joinable")
	}
	full := Config{Online: "true", Device: "echo wlan0", Networks: "true", Connect: "true"}
	if !radio(full).Joinable() {
		t.Error("a fully described tree reported not joinable")
	}
}

func TestInterfaceReturnsWhatTheDeviceCommandPrints(t *testing.T) {
	r := radio(Config{Device: "echo wlan0"})
	got, err := r.Interface()
	if err != nil {
		t.Fatal(err)
	}
	if got != "wlan0" {
		t.Errorf("interface = %q, want wlan0", got)
	}
}

func TestInterfaceFailsWhenThereIsNoDevice(t *testing.T) {
	if _, err := radio(Config{Device: "true"}).Interface(); err == nil {
		t.Fatal("an empty device list was not an error")
	}
	if _, err := radio(Config{Device: "exit 1"}).Interface(); err == nil {
		t.Fatal("a failing device command was not an error")
	}
}

// An SSID may hold spaces, so the list is one name per line and nothing else.
func TestNetworksReadsOneNamePerLine(t *testing.T) {
	cfg := Config{Networks: `printf '%s\n' "Coffee Bar" Home`}
	got, err := radio(cfg).Networks("wlan0")
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"Coffee Bar", "Home"}
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Errorf("networks = %v, want %v", got, want)
	}
}

func TestNetworksFailsWhenTheHookDoes(t *testing.T) {
	if _, err := radio(Config{Networks: "exit 1"}).Networks("wlan0"); err == nil {
		t.Fatal("a failing networks hook was not reported")
	}
}

func TestNetworksSeesTheDeviceInTheEnvironment(t *testing.T) {
	cfg := Config{Networks: `echo "device=$WLAN_DEVICE"`}
	got, err := radio(cfg).Networks("wlan0")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0] != "device=wlan0" {
		t.Errorf("networks = %v", got)
	}
}

func TestJoinRunsConnectWithTheCredentials(t *testing.T) {
	cfg := Config{
		Online:  "true",
		Connect: `[ "$WLAN_DEVICE" = wlan0 ] && [ "$WLAN_SSID" = Home ] && [ "$WLAN_PASSPHRASE" = secret ]`,
	}
	if err := radio(cfg).Join("wlan0", "Home", "secret"); err != nil {
		t.Fatalf("join = %v", err)
	}
}

func TestJoinFailsWhenConnectFails(t *testing.T) {
	cfg := Config{Online: "true", Connect: "exit 1"}
	if err := radio(cfg).Join("wlan0", "Home", "secret"); err == nil {
		t.Fatal("a failing connect was not reported")
	}
}

// Joining and being online are not the same thing — a wrong passphrase fails
// silently on some cards — so Join has to wait and check for itself.
func TestJoinFailsWhenItNeverComesOnline(t *testing.T) {
	cfg := Config{Online: "false", Connect: "true"}
	err := radio(cfg).Join("wlan0", "Home", "secret")
	if err == nil {
		t.Fatal("a connection that never carries traffic was not reported")
	}
	if !strings.Contains(err.Error(), "still no internet") {
		t.Errorf("err = %v", err)
	}
}

func TestAHookIsHandedTheEnvironmentAsItStandsNow(t *testing.T) {
	env := exec.Env{"ANSWER=first"}
	r := &Radio{
		cfg:    Config{Online: "true", Networks: `printf '%s\n' "$ANSWER"`},
		sh:     sh,
		env:    func() exec.Env { return env },
		settle: time.Millisecond,
		tries:  2,
	}

	// An answer given after the radio was built. Every other shell in the
	// program is started with the environment as it stands; so is this one.
	env = exec.Env{"ANSWER=second"}

	lines, err := r.Networks("wlan0")
	if err != nil {
		t.Fatalf("Networks() = %v", err)
	}
	if len(lines) != 1 || lines[0] != "second" {
		t.Errorf("the hook was handed %q, want [second]", lines)
	}
}

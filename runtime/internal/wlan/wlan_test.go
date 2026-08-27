package wlan

import (
	"strings"
	"testing"
	"time"

	"installer/internal/exec"
	"installer/internal/spec"
)

var sh = exec.Runner{}

func radio(cfg *spec.Wlan) *Radio {
	return &Radio{cfg: cfg, sh: sh, settle: time.Millisecond, tries: 2}
}

func TestNewGivesNoRadioWhenTheTreeDescribesNone(t *testing.T) {
	if got := New(&spec.Spec{}, sh, nil); got != nil {
		t.Errorf("New() = %v, want nil", got)
	}
}

func TestOnlineReportsWhatTheCheckSays(t *testing.T) {
	r := radio(&spec.Wlan{Check: "true"})
	if !r.Online() {
		t.Error("Online() = false, want true")
	}
	r = radio(&spec.Wlan{Check: "false"})
	if r.Online() {
		t.Error("Online() = true, want false")
	}
}

func TestJoinableNeedsDeviceNetworksAndConnect(t *testing.T) {
	if (&Radio{cfg: &spec.Wlan{Check: "true"}}).Joinable() {
		t.Error("a check-only tree reported joinable")
	}
	full := &spec.Wlan{Check: "true", Device: "echo wlan0", Networks: "true", Connect: "true"}
	if !(&Radio{cfg: full}).Joinable() {
		t.Error("a fully described tree reported not joinable")
	}
}

func TestInterfaceReturnsWhatTheDeviceCommandPrints(t *testing.T) {
	r := radio(&spec.Wlan{Device: "echo wlan0"})
	got, err := r.Interface()
	if err != nil {
		t.Fatal(err)
	}
	if got != "wlan0" {
		t.Errorf("interface = %q, want wlan0", got)
	}
}

func TestInterfaceFailsWhenThereIsNoDevice(t *testing.T) {
	if _, err := radio(&spec.Wlan{Device: "true"}).Interface(); err == nil {
		t.Fatal("an empty device list was not an error")
	}
	if _, err := radio(&spec.Wlan{Device: "exit 1"}).Interface(); err == nil {
		t.Fatal("a failing device command was not an error")
	}
}

// Scanning and reading the list are one call because the second is never
// useful without the first having settled — see Radio.Networks.
func TestNetworksScansThenReadsTheList(t *testing.T) {
	cfg := &spec.Wlan{
		Scan:     "true",
		Networks: `printf '%s\n' "Coffee Bar" Home`,
	}
	got, err := radio(cfg).Networks("wlan0")
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"Coffee Bar", "Home"}
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Errorf("networks = %v, want %v", got, want)
	}
}

// A scan that fails is not fatal: the list might still hold something from a
// moment ago.
func TestNetworksToleratesAFailingScan(t *testing.T) {
	cfg := &spec.Wlan{Scan: "exit 1", Networks: "echo cached"}
	got, err := radio(cfg).Networks("wlan0")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0] != "cached" {
		t.Errorf("networks = %v", got)
	}
}

func TestNetworksSeesTheDeviceInTheEnvironment(t *testing.T) {
	cfg := &spec.Wlan{Networks: `echo "device=$WLAN_DEVICE"`}
	got, err := radio(cfg).Networks("wlan0")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0] != "device=wlan0" {
		t.Errorf("networks = %v", got)
	}
}

func TestJoinRunsConnectWithTheCredentials(t *testing.T) {
	cfg := &spec.Wlan{
		Check:   "true",
		Connect: `[ "$WLAN_DEVICE" = wlan0 ] && [ "$WLAN_SSID" = Home ] && [ "$WLAN_PASSPHRASE" = secret ]`,
	}
	if err := radio(cfg).Join("wlan0", "Home", "secret"); err != nil {
		t.Fatalf("join = %v", err)
	}
}

func TestJoinFailsWhenConnectFails(t *testing.T) {
	cfg := &spec.Wlan{Check: "true", Connect: "exit 1"}
	if err := radio(cfg).Join("wlan0", "Home", "secret"); err == nil {
		t.Fatal("a failing connect was not reported")
	}
}

// Joining and being online are not the same thing — a wrong passphrase fails
// silently on some cards — so Join has to wait and check for itself.
func TestJoinFailsWhenItNeverComesOnline(t *testing.T) {
	cfg := &spec.Wlan{Check: "false", Connect: "true"}
	err := radio(cfg).Join("wlan0", "Home", "secret")
	if err == nil {
		t.Fatal("a connection that never carries traffic was not reported")
	}
	if !strings.Contains(err.Error(), "still no internet") {
		t.Errorf("err = %v", err)
	}
}

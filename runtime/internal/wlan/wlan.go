// Package wlan joins a wireless network the way the tree says to.
//
// It knows that connecting means finding a device, scanning, listing what is
// out there and offering a passphrase — and nothing about which commands do
// that. Those live in the tree's installer.yaml (see internal/spec.Wlan),
// because they are the one part of this that is a property of the
// distribution rather than of the flow.
package wlan

import (
	"fmt"
	"time"

	"installer/internal/exec"
	"installer/internal/spec"
)

// Radio joins a network the way one tree describes.
type Radio struct {
	cfg *spec.Wlan
	sh  exec.Runner
	env exec.Env

	// How long a scan is given to settle and how many times a fresh connection
	// is given to come up. Fields rather than constants so a test can drive the
	// whole thing without waiting out a real radio.
	settle time.Duration
	tries  int
}

// The variables every command is handed, as far as they are known yet.
const (
	envDevice     = "WLAN_DEVICE"
	envSSID       = "WLAN_SSID"
	envPassphrase = "WLAN_PASSPHRASE"
)

// Defaults for a real radio. A scan returns as soon as it is *started* — iwctl
// does — so reading the list straight away finds nothing; and a fresh
// connection needs a DHCP lease before it carries anything.
const (
	defaultSettle = 3 * time.Second
	defaultTries  = 4
)

// New builds the tree's radio. A tree that describes no network gets a nil
// Radio, which is not an error — it just never gets offered the screen.
func New(sp *spec.Spec, sh exec.Runner, env exec.Env) *Radio {
	if sp.Wlan == nil {
		return nil
	}
	return &Radio{cfg: sp.Wlan, sh: sh, env: env, settle: defaultSettle, tries: defaultTries}
}

// Title and Description are the tree's own words for this screen.
func (r *Radio) Title() string       { return r.cfg.Label() }
func (r *Radio) Description() string { return r.cfg.Help() }

// Joinable reports whether the tree described enough to actually connect. A
// tree may declare only a check, which means "tell me if I am offline" and
// nothing more.
func (r *Radio) Joinable() bool { return r.cfg.Joinable() }

// Online reports whether there is internet. A failing check is an answer, not
// an error — being offline is the normal case this whole package exists for.
func (r *Radio) Online() bool {
	_, err := r.sh.Run(r.cfg.Check, r.env)
	return err == nil
}

// Interface finds the wireless device to use.
func (r *Radio) Interface() (string, error) {
	out, err := r.sh.Run(r.cfg.Device, r.env)
	if err != nil {
		return "", fmt.Errorf("no wireless device: %w", err)
	}
	if out == "" {
		return "", fmt.Errorf("no wireless device found")
	}
	return out, nil
}

// Networks scans and returns the networks in range. The scan and the read are
// one call because they are never useful apart: a list read before the scan
// has settled is empty, and that is not something a caller should have to
// know.
func (r *Radio) Networks(device string) ([]string, error) {
	env := r.withDevice(device)
	if r.cfg.Scan != "" {
		// A scan that fails is not fatal: the card may already hold results
		// from a moment ago, and an empty list says more than an error would.
		if _, err := r.sh.Run(r.cfg.Scan, env); err == nil {
			time.Sleep(r.settle)
		}
	}
	lines, err := r.sh.Lines(r.cfg.Networks, env)
	if err != nil {
		return nil, fmt.Errorf("cannot list networks: %w", err)
	}
	return lines, nil
}

// Join connects to one network and waits for it to actually carry traffic.
// Joining and being online are not the same thing — a wrong passphrase fails
// silently on some cards — so this reports the second, which is what the
// caller meant to ask.
func (r *Radio) Join(device, ssid, passphrase string) error {
	env := r.withCredentials(device, ssid, passphrase)
	if _, err := r.sh.Run(r.cfg.Connect, env); err != nil {
		return fmt.Errorf("could not join %s: %w", ssid, err)
	}
	for i := 0; i < r.tries; i++ {
		if r.Online() {
			return nil
		}
		time.Sleep(r.settle)
	}
	return fmt.Errorf("joined %s but there is still no internet", ssid)
}

func (r *Radio) withDevice(device string) exec.Env {
	return append(append(exec.Env{}, r.env...), envDevice+"="+device)
}

func (r *Radio) withCredentials(device, ssid, passphrase string) exec.Env {
	return append(r.withDevice(device), envSSID+"="+ssid, envPassphrase+"="+passphrase)
}

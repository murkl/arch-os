// Package wlan joins a wireless network the way the tree says to.
//
// It knows that connecting means finding a device, listing what is out there
// and offering a passphrase — and nothing about which commands do that. Those
// are the tree's hooks, because they are the one part of this that is a
// property of the distribution rather than of the flow.
package wlan

import (
	"errors"
	"fmt"
	"time"

	"installer/internal/exec"
	"installer/internal/i18n"
)

// Config is the shell one tree uses to find and join a network. Every field is
// optional bar Online: a tree may say only "tell me if I am offline".
type Config struct {
	Online   string
	Device   string
	Networks string
	Connect  string
}

// Radio joins a network the way one tree describes.
type Radio struct {
	cfg Config
	sh  exec.Runner

	// What a hook is handed, asked for rather than kept: this outlives several
	// answers being given, and every other shell in the program is started with
	// the environment as it stands rather than as it was.
	env func() exec.Env

	// How long a fresh connection is given to come up, and how many times it is
	// looked at. Fields rather than constants so a test can drive the whole
	// thing without waiting out a real radio.
	settle time.Duration
	tries  int
}

// The variables every command is handed, as far as they are known yet.
const (
	envDevice     = "WLAN_DEVICE"
	envSSID       = "WLAN_SSID"
	envPassphrase = "WLAN_PASSPHRASE"
)

// Defaults for a real radio: a fresh connection needs a DHCP lease before it
// carries anything.
const (
	defaultSettle = 3 * time.Second
	defaultTries  = 4
)

// New builds the tree's radio. A tree that cannot even say whether it is online
// gets a nil Radio, which is not an error — it just never gets offered the
// screen.
func New(cfg Config, sh exec.Runner, env func() exec.Env) *Radio {
	if cfg.Online == "" {
		return nil
	}
	return &Radio{cfg: cfg, sh: sh, env: env, settle: defaultSettle, tries: defaultTries}
}

// Joinable reports whether the tree described enough to actually connect.
func (r *Radio) Joinable() bool {
	return r.cfg.Device != "" && r.cfg.Networks != "" && r.cfg.Connect != ""
}

// Online reports whether there is internet. A failing check is an answer, not
// an error — being offline is the normal case this whole package exists for.
func (r *Radio) Online() bool {
	_, err := r.sh.Run(r.cfg.Online, r.env())
	return err == nil
}

// Interface finds the wireless device to use.
//
// What comes back here is read on the network page rather than in the log, so
// it is said in the interface's own language with whatever the hook had to add
// after it — that part is the tool's own words and is nobody's to translate.
func (r *Radio) Interface() (string, error) {
	out, err := r.sh.Run(r.cfg.Device, r.env())
	if err != nil {
		return "", fmt.Errorf("%s: %w", i18n.T("No wireless device."), err)
	}
	if out == "" {
		return "", errors.New(i18n.T("No wireless device."))
	}
	return out, nil
}

// Networks returns the networks in range. Scanning and waiting for the results
// to settle belong to the hook: how long a card takes to answer is the tree's
// business, and a list read too early is empty rather than wrong.
func (r *Radio) Networks(device string) ([]string, error) {
	lines, err := r.sh.Lines(r.cfg.Networks, r.withDevice(device))
	if err != nil {
		return nil, fmt.Errorf("%s: %w", i18n.T("The networks in range could not be read."), err)
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
		// TRANSLATORS: %s is the name of the wireless network.
		return fmt.Errorf("%s: %w", i18n.T("%s could not be joined.", ssid), err)
	}
	for i := 0; i < r.tries; i++ {
		if r.Online() {
			return nil
		}
		time.Sleep(r.settle)
	}
	// TRANSLATORS: %s is the name of the wireless network.
	return errors.New(i18n.T("%s was joined, but there is still no internet.", ssid))
}

func (r *Radio) withDevice(device string) exec.Env {
	return append(append(exec.Env{}, r.env()...), envDevice+"="+device)
}

func (r *Radio) withCredentials(device, ssid, passphrase string) exec.Env {
	return append(r.withDevice(device), envSSID+"="+ssid, envPassphrase+"="+passphrase)
}

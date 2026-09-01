<h1 align="center">
  <img src="./logo.svg" width="150" height="150">
  <p>Arch OS</p>
</h1>

<div align="center">

<p><strong>One command, on your own machine to get a boot device — and on the machine that device booted.</strong></p>

<p><code>curl -Ls bit.ly/arch-os | bash</code></p>

<p><img src="./screenshots/installer.png"></p>

<p>A minimal, reproducible Arch Linux base — tty-only or with a full GNOME desktop.</p>

<p>
  <img src="https://img.shields.io/badge/MAINTAINED-YES-green?style=for-the-badge">
  <img src="https://img.shields.io/badge/License-GPL_3.0-blue?style=for-the-badge">
</p>

</div>

## What this is

Two things, on purpose kept apart — see
[CONTRIBUTING.md](../CONTRIBUTING.md) for how a change gets from a branch to a
release. **[`runtime/`](../runtime)** is a Go binary that draws the
interface, asks questions, keeps the answers and runs shell in order; it knows
nothing about Arch. **[`setup/`](../setup)** is everything that does: one
`installer.yaml` and the folders beside it, describing exactly the Arch Linux
install below. **[`iso/`](../iso)** turns a build of both into a bootable
image that starts the installer the moment it boots.

## Features

- Minimal Arch Linux base, GNOME desktop optional (full or slim)
- Disk encryption (LUKS2), filesystem btrfs or ext4
- BTRFS snapshots (Snapper) with an optional Btrfs Assistant GUI for rollback
- Dual boot aware partitioning
- Bootloader (systemd-boot or GRUB) and kernel are both a choice, not a default
- Secure Boot, on by default where the boot chain can be signed: own keys, a
  signed unified kernel image, re-signed on every kernel update
- Graphics driver selection (Mesa, Intel, NVIDIA, AMD)
- Plymouth bootsplash, Nord-themed
- AUR helper, 32-bit (multilib) support, automatic housekeeping
- Shell enhancement (bash, zsh or fish), preinstalled system manager TUI
- Samba share, automatic mirror ranking by country (reflector)
- Shareable configuration: an installation offers — after it has finished, and
  opening on no — to put its answers online and hand back a QR code, and the next
  machine is set up from that code in one question
- Multilingual interface (English, German); a tree can add its own languages
  without touching the runtime — see [runtime/README.md](../runtime/README.md#translations)

## Installing

An internet connection is required — most packages are downloaded during
installation.

```sh
curl -Ls bit.ly/arch-os | bash
```

The same command twice, and where it runs decides what it does — see
[`get.sh`](../get.sh):

1. **On your own machine** it fetches the latest Arch OS image, verifies its
   checksum and writes it to a USB device you pick from the ones plugged in.
   ([Ventoy](https://www.ventoy.net) or `dd` do just as well.)
2. **UEFI, Secure Boot off.** The installer checks this on startup and
   refuses to run otherwise — it can turn Secure Boot back on for you once
   the system exists.
3. **Boot from the USB device.** The installer starts on its own. No
   keyboard layout or network step is needed beforehand: the interface asks
   for a keymap, and a machine with no link is told to connect one with
   `iwctl` before it will go any further.

On a stock [Arch Linux ISO](https://archlinux.org/download/) the same command
is what starts an installation: it fetches the latest release, unpacks it and
runs it. `MODE=install|create` picks either half by hand, and `DEBUG=true`
keeps both off the hardware.

`Ctrl+C` asks what to do with the machine — restart it or switch it off — and
does not drop out into a blank console: there is nothing behind the installer to
drop out into. Every answer is written the moment it is given, so nothing
already answered has to be answered twice on the next boot.

## Maintenance

<p><img src="./screenshots/manager_menu.png"></p>

Most of what an installed system needs done regularly is handled by the
preinstalled system manager: package and Flatpak updates, `pacdiff`, Snapper
housekeeping. Worth doing by hand regardless:

- Read the **[Arch Linux news](https://www.archlinux.org/news)** before a
  big upgrade
- Consult the **[Arch Linux Wiki](https://wiki.archlinux.org)** when something
  breaks
- Roll back with Btrfs Assistant (or `snapper`) if it does, and a snapshot
  exists to roll back to
- Boot the installation image and choose **Recovery** if it no longer starts at
  all: it unlocks the disk, puts a snapshot back in place of the root subvolume,
  rebuilds the kernel images from the package cache and hands you a shell inside
  the repaired system — without needing a network

<details>
<summary><h2 style="display: inline;" id="screenshots">Screenshots</h2></summary>

<div align="center">
  <p><div><img src="./screenshots/desktop_overview.jpg"></div><sub><i>Desktop</i></sub></p>
  <p><div><img src="./screenshots/bootsplash.png"></div><sub><i>Bootsplash</i></sub></p>
  <p><div><img src="./screenshots/starship.png"></div><sub><i>Shell prompt</i></sub></p>
  <p><div><img src="./screenshots/fastfetch.png"></div><sub><i>System info</i></sub></p>
  <p><div><img src="./screenshots/desktop_apps.png"></div><sub><i>Desktop core apps</i></sub></p>
  <p><div><img src="./screenshots/manager_dashboard.png"></div><sub><i>System manager</i></sub></p>
  <p><div><img src="./screenshots/recovery.png"></div><sub><i>BTRFS rollback</i></sub></p>
</div>

</details>

## Credit

The Arch Linux logic is a port of
[murkl/arch-os](https://github.com/murkl/arch-os), whose `installer.sh` the
shell in [`setup/`](../setup) was carved out of.

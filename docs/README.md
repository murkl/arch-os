<h1 align="center">
  <img src="./logo.svg" width="140" height="140">
  <p>Arch OS</p>
</h1>

<div align="center">

<p><strong>A minimal, reproducible Arch Linux base — tty-only or with a full GNOME desktop.</strong></p>

<p><code>curl -Ls bit.ly/arch-os | bash</code></p>

<p>
  <img src="https://img.shields.io/badge/MAINTAINED-YES-green?style=for-the-badge">
  <img src="https://img.shields.io/badge/License-GPL_3.0-blue?style=for-the-badge">
</p>

<p><img src="./screenshots/installer.png" width="820"></p>

</div>

## What you get

- Minimal Arch Linux base, with an optional GNOME desktop (full or slim)
- LUKS2 disk encryption, with Btrfs or ext4
- Btrfs snapshots (via Snapper), taken automatically before every package change
- Secure Boot with your own keys, and a signed unified kernel image that is
  re-signed on every kernel update
- Your choice of bootloader (systemd-boot or GRUB) and kernel
- Dual-boot aware partitioning
- Graphics drivers (Mesa, Intel, NVIDIA, AMD) and a Plymouth boot splash
- AUR helper, 32-bit support, automatic housekeeping timers
- Shell enhancements (bash, zsh or fish) and a system manager TUI
- Samba file sharing, mirrors ranked by country
- English and German interface — [more languages are welcome](../TRANSLATING.md);
  a module can add its own
- A recovery mode on the same image, to roll back a broken system without
  needing a network connection

## Installing

You need a UEFI machine with Secure Boot turned off and an internet
connection. Run the same command twice — what it does depends on where you
run it:

```sh
curl -Ls bit.ly/arch-os | bash
```

1. **On your own machine**, it downloads the latest image, verifies its
   checksum, and writes it to a USB drive you choose.
   ([Ventoy](https://www.ventoy.net) or `dd` work just as well.)
2. **Boot the target machine from that drive.** It starts on its own and asks
   whether to install a new system or repair one already there — no keymap or
   network setup first.
3. **Answer the questions.** Every answer is saved as soon as you give it, so
   an interrupted installation picks up right where it left off.

On a stock [Arch Linux ISO](https://archlinux.org/download/), the same
command takes you straight to that same question: it downloads the latest
release, unpacks it, and runs it. Set `MODE=install` or `MODE=create` to skip
the choice, and `DEBUG=true` to try it without touching any hardware.

<p><img src="./screenshots/setup.png" width="820"></p>

### Reusing your answers

At the end of an installation, you can share your answers as a short code or
as an `installer.conf` file. Place that file next to the installer and every
question it answers is skipped — handy for setting up the same kind of
machine more than once.

`installer --debug` runs through the whole installer without touching a disk.

## Maintenance

<p><img src="./screenshots/manager_menu.png" width="420"></p>

The preinstalled system manager handles routine maintenance: package and
Flatpak updates, `pacdiff`, and Snapper housekeeping. A few things are still
worth doing yourself:

- Read the [Arch Linux news](https://www.archlinux.org/news) before a big
  upgrade
- Roll back with Btrfs Assistant (or `snapper`) if an update breaks something
- Boot the installation image and choose **Arch OS Recovery** if the system
  won't start at all: it unlocks the disk, restores a snapshot in place of the
  root subvolume, rebuilds the kernel images from the package cache, and drops
  you into a shell inside the repaired system — no network needed

<p><img src="./screenshots/recovery.png" width="820"></p>

## How it is built

Four parts, kept deliberately separate — see
[CONTRIBUTING.md](../CONTRIBUTING.md) for more.

| | |
|---|---|
| [`runtime/`](../runtime) | A Go binary that draws the interface, asks the questions, and runs shell scripts in order. It knows nothing about Arch Linux, disks or packages — none of those words appear in it. |
| [`modules/installer/`](../modules/installer) | Everything that does the actual work: one `installer.yaml`, the questions it asks, and a folder for each step of the installation. |
| [`modules/recovery/`](../modules/recovery) | The same shape again, for repairing a system already on disk: its own `recovery.yaml`, its own steps, its own answers. |
| [`iso/`](../iso) | Turns a build of the three into a bootable image. |

The installer and recovery are modules — data, not programs. One binary runs
either of them, picked from a folder beside it. A release is that binary plus
a `modules/` folder holding both, and a `runtime.yaml` describing them
together: the first page is the language, the second is which module to open.
Adding a question is a few lines of YAML; adding a step is a folder with two
files; adding a whole module is a folder in `modules/`. None of that touches
the runtime, and the runtime can never break Arch-specific behavior it
doesn't know about.

<details>
<summary><h2 style="display: inline;" id="screenshots">More screenshots</h2></summary>

<div align="center">
  <p><div><img src="./screenshots/installing.png"></div><sub><i>Installing</i></sub></p>
  <p><div><img src="./screenshots/desktop_overview.jpg"></div><sub><i>Desktop</i></sub></p>
  <p><div><img src="./screenshots/desktop_apps.png"></div><sub><i>Desktop core apps</i></sub></p>
  <p><div><img src="./screenshots/bootsplash.png"></div><sub><i>Boot splash</i></sub></p>
  <p><div><img src="./screenshots/starship.png"></div><sub><i>Shell prompt</i></sub></p>
  <p><div><img src="./screenshots/fastfetch.png"></div><sub><i>System info</i></sub></p>
  <p><div><img src="./screenshots/manager_dashboard.png"></div><sub><i>System manager</i></sub></p>
</div>

</details>

## Why this exists

Arch OS is a side project, and it installs the system I use every day — at
work and at home, as a project lead and cloud native engineer. It all started
with Ubuntu, back in 2005.

The two halves are also written differently. The runtime is Go, written with
AI assistance and reviewed line by line before it's merged. The Arch Linux
side — the installer, the recovery module, the shell scripts, and the YAML —
is handwritten, and grew out of the installer that existed before there was a
runtime to drive it.

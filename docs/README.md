<div align="center">

<img src="logo.svg" width="150" alt="">

<h1>Arch OS</h1>

<p><strong>A minimal and robust Arch Linux base — a text console or a GNOME desktop — with an Installer and a Recovery on one bootable image.</strong></p>

<p>
  <img src="https://img.shields.io/github/v/release/murkl/arch-os?style=for-the-badge&label=RELEASE&color=1793d1" alt="">
  <img src="https://img.shields.io/badge/License-GPL_3.0-blue?style=for-the-badge" alt="">
  <img src="https://img.shields.io/badge/UEFI-x86__64-2e3440?style=for-the-badge" alt="">
</p>

<img src="screenshots/installer.png" alt="The Installer, asking what kind of system to put on this machine">

<p>Boot the latest <b><a href="https://github.com/murkl/arch-os/releases/latest">Arch OS ISO</a></b> and the Installer starts on its own. No keyboard layout to load, no network to configure, no command to type.</p>

<p>Or run this on any Linux machine to write that ISO to a USB device — and from a booted <a href="https://archlinux.org/download/">Arch Linux ISO</a>, the same command starts the Installer instead:</p>

**`curl -Ls raw.githubusercontent.com/murkl/arch-os/main/get.sh | bash`**

<p><b>

[➜ Step by Step](#installation) · [➜ Screenshots](#screenshots) · [➜ Contributing](CONTRIBUTING.md) · [➜ t.me/archos_community](https://t.me/archos_community)

</b></p>

</div>

## Features

**Core**

- Minimal Arch Linux base, UEFI only
- Kernel: linux-zen, linux, linux-lts or linux-hardened
- File system btrfs or ext4, with disk encryption (LUKS2)
- Boot loader: systemd-boot or GRUB
- Secure Boot with own keys and a signed Unified Kernel Image, re-signed on every kernel update
- Btrfs snapshots (Snapper), taken before every package change
- Dual boot aware partitioning
- One password for encryption, root and user
- Swap with zram-generator (zstd), systemd OOM, fstrim, microcode, NetworkManager
- Mirrors ranked by country (reflector)
- English and German interface

**Desktop** (optional)

- GNOME, Wayland optimized
- Slim version: GNOME Core Apps only
- Graphics driver: Mesa, Intel i915, NVIDIA, AMD or ATI
- Extras: codecs, fonts, printing, network protocols and everyday applications
- Samba public and home share
- Automatic login, following disk encryption by default — one password prompt in total

**On top**

- [Arch OS Bootsplash](https://github.com/murkl/plymouth-theme-arch-os), Manager, Shell Enhancement (bash, zsh or fish) and automatic housekeeping
- Arch OS Recovery on the same image, works without a network connection
- AUR helper, 32-bit support (multilib) and virtual machine support

## Installation

An internet connection is required: most packages are downloaded during the installation.

### 1. Prepare a bootable USB Device

- Download the latest ISO from **[the release page](https://github.com/murkl/arch-os/releases/latest)** and write it with **[Ventoy](https://www.ventoy.net/en/download.html)** or any ISO writer
- Or let this download, verify and write it for you, on any Linux machine:

```
curl -Ls raw.githubusercontent.com/murkl/arch-os/main/get.sh | bash
```

**Note:** _Downloads are kept in `~/Downloads` and reused, so a second run costs no bandwidth._

### 2. Set the Firmware up

- Boot mode: UEFI
- Secure Boot: off — the Installer sets it up again for you afterwards

### 3. Boot from the USB Device

The Installer starts on its own. It asks for the interface language, then whether to install a new system or repair an existing one.

<p><img src="screenshots/setup.png" alt="The page that asks which of the two to open"></p>

**Note:** _From a booted official **[Arch Linux ISO](https://archlinux.org/download/)** the same `get.sh` command downloads the latest release and starts it directly. Which of its two halves runs is worked out from where it runs._

| Variable | Description |
| --- | --- |
| `MODE=install` | Run the Installer here, instead of writing a USB device |
| `MODE=create` | Write a USB device, instead of running the Installer here |
| `DEBUG=true` | Touch no hardware: downloads still happen, no device is written, the run is simulated |
| `DOWNLOAD_DIR=<dir>` | Where downloads are kept (default `~/Downloads`) |

**Note:** _These are read by the shell on the right of the pipe: `curl -Ls … | DEBUG=true bash`_

### 4. Reuse your Answers

Every answer is written to `installer.conf` the moment it is given, so an interrupted run picks up where it left off. The password is not: it is asked right before the installation starts and never reaches disk.

- **Share it:** at the end of a run the answers can be uploaded to **[paste.rs](https://paste.rs)**. What comes back is a short code, shown as a QR code and as the address it belongs to. The next installation offers a starting point that asks for exactly that code
- **Copy it:** put `installer.conf` next to the Installer on another machine and every question it answers is skipped

**Note:** _Nothing leaves the machine until you say so, and every imported answer can still be changed afterwards._

## Recovery

<p><img src="screenshots/recovery.png" alt="The Recovery, opening a system already on disk"></p>

To rescue an Arch OS after a crash, boot the same ISO and choose **Arch OS Recovery**.

- Unlocks and mounts the installation at `/mnt`
- Puts a Btrfs snapshot back in place of the root subvolume
- Rebuilds the kernel images and initramfs from the local package cache
- Opens a shell inside the repaired system

**Note:** _The Recovery downloads nothing and needs no network connection, because a broken network may be part of the problem._

## Maintenance

<p><img src="screenshots/manager_menu.png" alt="The Arch OS System Manager"></p>

After installing with the default starting point, most of it happens on its own through the preinstalled **Arch OS System Manager**: package and Flatpak updates, `pacdiff` and Snapper housekeeping. What is left to do by hand:

- Read the **[Arch Linux News](https://www.archlinux.org/news)**, preferably before upgrading
- Roll back with **Btrfs Assistant** or `snapper` if an update breaks something
- Consult the **[Arch Linux Wiki](https://wiki.archlinux.org)** if you need help

<details>

<summary><h2 style="display: inline;" id="screenshots">Screenshots</h2></summary>

<div align="center">
  <p><div><img src="screenshots/installing.png"></div><sub><i>Installer</i></sub></p>
  <p><div><img src="screenshots/desktop_overview.jpg"></div><sub><i>Desktop</i></sub></p>
  <p><div><img src="screenshots/desktop_apps.png"></div><sub><i>Desktop Core Apps</i></sub></p>
  <p><div><img src="screenshots/bootsplash.png"></div><sub><i>Bootsplash</i></sub></p>
  <p><div><img src="screenshots/starship.png"></div><sub><i>Shell Enhancement</i></sub></p>
  <p><div><img src="screenshots/fastfetch.png"></div><sub><i>Fetch</i></sub></p>
  <p><div><img src="screenshots/manager_dashboard.png"></div><sub><i>System Manager</i></sub></p>
</div>

</details>

## Development

Arch OS is four parts, kept deliberately apart:

| Part | Description |
| --- | --- |
| [Oak](https://github.com/murkl/oak) | The runtime, a repository of its own. One Go binary that draws the interface, asks the questions and runs the shell scripts in order. Knows nothing about Arch Linux, disks or packages |
| [`modules/installer/`](../modules/installer) | Everything that does the actual work: one `installer.yaml`, the questions it asks and a folder per step |
| [`modules/recovery/`](../modules/recovery) | The same shape again, for repairing a system already on disk |
| [`iso/`](../iso) | Turns a build of the three into a bootable image |

Installer and Recovery are modules: data, not programs. One binary runs either of them, and a release is that binary with a `modules/` folder and an `oak.yaml` beside it. The build downloads the binary rather than compiling it, so nothing here needs a Go toolchain.

- Adding a question is a few lines of YAML
- Adding a step is a folder with two files
- Adding a module is a folder under `modules/`

**[➜ See Contributing](CONTRIBUTING.md)** for branches, releases and how a commit becomes an image.

## License

GPL-3.0. See **[LICENSE](../LICENSE)**.

## Credits

Many thanks to these projects and the people behind them!

- **[Arch Linux](https://archlinux.org)**
- **[GNOME](https://www.gnome.org)**
- **[Bubble Tea](https://github.com/charmbracelet/bubbletea)** by charm

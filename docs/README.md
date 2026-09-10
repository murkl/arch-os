<div align="center">

<img src="logo.svg" width="150" alt="">

<h1>Arch OS</h1>

<p><strong>A minimal, robust and reproducible Arch Linux base, as a text console or a GNOME desktop, with an Installer and a Recovery on one bootable image.</strong></p>

<p>
  <img src="https://img.shields.io/github/v/release/murkl/arch-os?style=for-the-badge&label=RELEASE&color=1793d1" alt="">
  <img src="https://img.shields.io/badge/License-GPL_3.0-blue?style=for-the-badge" alt="">
  <img src="https://img.shields.io/badge/UEFI-x86__64-2e3440?style=for-the-badge" alt="">
</p>

<img src="screenshots/installer.png" alt="The Installer, asking what kind of system to put on this machine">

<p>Boot the latest <b><a href="https://github.com/murkl/arch-os/releases/latest">Arch OS ISO</a></b> and the Installer starts on its own. No keyboard layout to load, no network to configure, no command to type.</p>

<p>Or run this on any Linux machine to write that ISO to a USB device. From a booted <a href="https://archlinux.org/download/">Arch Linux ISO</a> the same command starts the Installer instead:</p>

**`curl -Ls bit.ly/arch-os | bash`**

<p><b>

[➜ Step by Step](#installation) · [➜ Screenshots](#screenshots) · [➜ Contributing](CONTRIBUTING.md) · [➜ t.me/archos_community](https://t.me/archos_community)

</b></p>

</div>

## Features

- Minimal Arch Linux base, UEFI only, with linux-zen, linux, linux-lts or linux-hardened
- File system btrfs or ext4, boot loader systemd-boot or GRUB, dual boot aware partitioning
- Disk encryption (LUKS2) and Secure Boot with own keys, signed again on every kernel update
- One password for encryption, root and user, and automatic login behind an encrypted disk
- Btrfs snapshots taken before every package change (Snapper), restored from the desktop (Btrfs Assistant)
- GNOME, Wayland optimized, with graphics driver (Mesa, Intel i915, NVIDIA, AMD or ATI), or a text console with nothing graphical on it
- Desktop extras: codecs, fonts, printing, network protocols, everyday applications and Samba shares
- Slim version: GNOME Core Apps only
- Swap with zram-generator (zstd), systemd OOM, fstrim, microcode, NetworkManager and mirrors ranked by country (reflector)
- AUR helper, 32-bit support (multilib), container engine (Docker or Podman), virtual machine support and automatic housekeeping
- [Arch OS Bootsplash](https://github.com/murkl/plymouth-theme-arch-os), System Manager and Shell Enhancement (bash, zsh or fish)
- Arch OS Recovery on the same image, works without a network connection
- Two starting points, Desktop or Minimal, with every question behind them still answerable
- English and German interface

## Installation

An internet connection is required: most packages are downloaded during the installation.

### 1. Prepare a bootable USB Device

- Download the latest ISO from **[the release page](https://github.com/murkl/arch-os/releases/latest)** and write it with **[Ventoy](https://www.ventoy.net/en/download.html)** or any ISO writer
- Or let this download, verify and write it for you, on any Linux machine:

```
curl -Ls bit.ly/arch-os | bash
```

**Note:** _Downloads are kept in `~/Downloads` and reused, so a second run costs no bandwidth. `DOWNLOAD_DIR` points somewhere else, `DEBUG=true` writes no device, and `MODE=install` or `MODE=create` picks the half by hand instead of by where the command runs: `curl -Ls bit.ly/arch-os | DEBUG=true bash`_

### 2. Set the Firmware up

- Boot mode: UEFI
- Secure Boot: off, the Installer sets it up again for you afterwards

### 3. Boot from the USB Device

The Installer starts on its own. It asks for the interface language, then whether to install a new system or repair an existing one.

<p><img src="screenshots/setup.png" alt="The page that asks which of the two to open"></p>

**Note:** _From a booted official **[Arch Linux ISO](https://archlinux.org/download/)** the same command downloads the latest release and starts it here instead of writing a device._

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
| [Oak](https://github.com/murkl/oak) | The runtime, a repository of its own. One binary that draws the interface, asks the questions and runs the shell scripts in order. Knows nothing about Arch Linux, disks or packages |
| [`modules/installer/`](../modules/installer) | Everything that does the actual work: one `module.yaml`, the questions it asks and a folder per step |
| [`modules/recovery/`](../modules/recovery) | The same shape again, for repairing a system already on disk |
| [`iso/`](../iso) | Turns a build of the three into a bootable image |

Installer and Recovery are modules: data, not programs. One binary runs either of them, `oak --module=installer` opens one outright, and a release is that binary with `oak.yaml` and `modules/` beside it. The build downloads the binary rather than compiling it, so nothing here needs a Go toolchain.

- Adding a question is a few lines of YAML
- Adding a step is a folder under the stage it belongs to
- Adding a module is a folder under `modules/`

**[➜ See Contributing](CONTRIBUTING.md)** for branches, releases and how a commit becomes an image.

## License

GPL-3.0. See **[LICENSE](../LICENSE)**.

## Credits

Many thanks to these projects and the people behind them!

- **[Arch Linux](https://archlinux.org)**
- **[GNOME](https://www.gnome.org)**
- **[Oak](https://github.com/murkl/oak)**
- **[Bubble Tea](https://github.com/charmbracelet/bubbletea)** by charm

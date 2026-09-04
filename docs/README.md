<h1 align="center">
  <img src="./logo.svg" width="150" height="150">
  <p>Arch OS</p>
</h1>

<div align="center">

<p><strong>Boot from latest <a target="_blank" href="https://github.com/murkl/arch-os/releases/latest">Arch OS ISO</a> to launch the Installer automatically.</strong></p>

<p>Alternatively run this on any machine to write the ISO to a USB device, or from a booted <a target="_blank" href="https://archlinux.org/download/">Arch Linux ISO</a> to start the Installer:</p>

**`curl -Ls raw.githubusercontent.com/murkl/arch-os/main/get.sh | bash`**

<p><b>

[➜ Step by Step Installation](#arch-os-installation)

</b></p>

<p><img src="./screenshots/installer.png"></p>

<p><b>

[➜ More Screenshots](#screenshots)

</b></p>

<p>This project provides a minimal and robust Arch Linux base (minimal tty core or GNOME desktop), along with an easy-to-use Installer and a Recovery mode on the same image. Every answer is saved as you give it, so an interrupted run picks up where it left off.</p>

## More Information

<p>
  <img src="https://img.shields.io/badge/MAINTAINED-YES-green?style=for-the-badge">
  <img src="https://img.shields.io/badge/License-GPL_3.0-blue?style=for-the-badge">
</p>

**[➜ Contributing](CONTRIBUTING.md)**<br>
**[➜ Translating](TRANSLATING.md)**<br>
<b><a about="_blank" href="https://t.me/archos_community">➜ t.me/archos_community</a></b>

</div>

## Core Features

- Minimal Arch Linux base
- Kernel: linux-zen, linux, linux-lts or linux-hardened
- Filesystem btrfs or ext4
- Disk Encryption (LUKS2)
- Bootloader: systemd-boot or grub
- Secure Boot with own keys and signed Unified Kernel Image (auto re-signed on kernel update)
- BTRFS Snapshot Support (Snapper, snapshot before every package change)
- Dual Boot aware partitioning
- All-in-One password (encryption, root & user)
- Swap with zram-generator (zstd)
- Network Manager
- Systemd OOM (out-of-memory killer)
- SSD Support (fstrim)
- Microcode Support (Intel & AMD)
- Mirrors ranked by country (reflector)
- English & German interface
- UEFI only supported

## Desktop Features

- GNOME Desktop Environment (optional)
- Arch OS Slim Version (GNOME Core Apps only)
- Graphics Driver (Mesa, Intel i915, NVIDIA, AMD, ATI)
- Desktop Extras: codecs, fonts, printing, network protocols and everyday applications
- Samba public & home share
- Auto GNOME Login (follows Disk Encryption by default, one password prompt total)
- Wayland optimized

## Additional Features

- Arch OS Core Tweaks
- [Arch OS Bootsplash](https://github.com/murkl/plymouth-theme-arch-os)
- Arch OS System Manager
- Arch OS Shell Enhancement (bash, zsh or fish)
- Arch OS Automatic Housekeeping
- Arch OS Recovery on the same image, works without a network connection
- AUR Helper (configurable)
- 32 Bit Support (Multilib)
- VM Support (optional)

## Arch OS Installation

To install Arch OS, an internet connection is required, as many packages will be downloaded during the installation process.

### 1. Prepare bootable USB Device

- Download latest Arch OS ISO from **[GitHub](https://github.com/murkl/arch-os/releases/latest)**
- Use **[Ventoy](https://www.ventoy.net/en/download.html)** or your prefered iso writer tool to create a bootable USB device
- Alternatively run this on any Linux machine to download, verify and write the ISO for you:

```
curl -Ls raw.githubusercontent.com/murkl/arch-os/main/get.sh | bash
```

**Note:** _Downloads are kept in `~/Downloads` and reused, so a second run costs no bandwidth._

### 2. Configure BIOS / UEFI Settings

- Disable Secure Boot
- Set Boot Mode to UEFI

### 3. Boot from USB Device

The Installer starts automatically. No keyboard layout to load, no network to configure, no command to type.

It first asks for the interface language, then whether to install a new system or repair an existing one.

<p><img src="./screenshots/setup.png"></p>

#### Without the Arch OS ISO

From a booted official **[Arch Linux ISO](https://archlinux.org/download/)** the same command downloads the latest release and starts it directly:

```
curl -Ls raw.githubusercontent.com/murkl/arch-os/main/get.sh | bash
```

**Note:** _Which of the two halves runs is worked out from where the command runs._

| Variable | Description |
| --- | --- |
| `MODE=install` | Run the Installer here, instead of writing a USB device |
| `MODE=create` | Write a USB device, instead of running the Installer here |
| `DEBUG=true` | Touch no hardware: downloads still happen, no device is written and the run is simulated |
| `DOWNLOAD_DIR=<dir>` | Where downloads are kept (default `~/Downloads`) |

**Note:** _These are read by the shell on the right of the pipe: `curl -Ls raw.githubusercontent.com/murkl/arch-os/main/get.sh | DEBUG=true bash`_

### 4. Reuse your Answers

Every answer is written to `installer.conf` as you give it. The password is not: it is asked right before the installation starts and never reaches disk.

- **Share it:** at the end of a run the answers can be uploaded to **[paste.rs](https://paste.rs)**. What comes back is a short code, shown as a QR code and as the address it belongs to. The next installation offers a preset that asks for exactly that code
- **Copy it:** place `installer.conf` next to the Installer on another machine and every question it answers is skipped

**Note:** _Nothing leaves the machine until you say so, and every imported answer can still be changed afterwards._

## System Maintenance

<p><img src="./screenshots/manager_menu.png"></p>

After installing Arch OS with the default preset, most maintenance tasks are performed automatically by the preinstalled **Arch OS System Manager**: package and Flatpak updates, `pacdiff` and Snapper housekeeping. The following steps must be executed manually on a regular basis:

- Regularly read the **[Arch Linux News](https://www.archlinux.org/news)** (preferably before upgrading your system)
- Roll back with **Btrfs Assistant** or `snapper` if an update breaks something
- Consult the **[Arch Linux Wiki](https://wiki.archlinux.org)** (if you need help)

## Arch OS Recovery

<p><img src="./screenshots/recovery.png"></p>

If you need to rescue your Arch OS in case of a crash, boot from the **[Arch OS ISO](#1-prepare-bootable-usb-device)** and choose **Arch OS Recovery**.

- Unlocks and mounts the installation at `/mnt`
- Puts a BTRFS snapshot back in place of the root subvolume
- Rebuilds the kernel images and initramfs from the local package cache
- Opens a shell inside the repaired system

**Note:** _The Recovery downloads nothing and needs no network connection, because a broken network may be part of the problem._

## Development

Arch OS is built as four parts, kept deliberately apart:

| Part | Description |
| --- | --- |
| [Oak](https://github.com/murkl/oak) | The runtime, a repository of its own. One Go binary that draws the interface, asks the questions and runs the shell scripts in order. Knows nothing about Arch Linux, disks or packages |
| [`modules/installer/`](../modules/installer) | Everything that does the actual work: one `installer.yaml`, the questions it asks and a folder per step |
| [`modules/recovery/`](../modules/recovery) | The same shape again, for repairing a system already on disk |
| [`iso/`](../iso) | Turns a build of the three into a bootable image |

Installer and Recovery are modules: data, not programs. One binary runs either of them. A release is that binary with a `modules/` folder and an `oak.yaml` beside it, and the build downloads the binary rather than compiling it.

- Adding a question is a few lines of YAML
- Adding a step is a folder with two files
- Adding a module is a folder under `modules/`

**Note:** _None of that touches Oak._

**[➜ See Contributing](CONTRIBUTING.md)** for branches, releases and how a commit becomes an image.

<details>

<summary><h2 style="display: inline;" id="screenshots">Screenshots</h2></summary>

<div align="center">
  <p><div><img src="./screenshots/installing.png"></div><sub><i>Installer Demo</i></sub></p>
  <p><div><img src="./screenshots/desktop_overview.jpg"></div><sub><i>Desktop Demo</i></sub></p>
  <p><div><img src="./screenshots/desktop_apps.png"></div><sub><i>Desktop Core Apps Demo</i></sub></p>
  <p><div><img src="./screenshots/bootsplash.png"></div><sub><i>Bootsplash Demo</i></sub></p>
  <p><div><img src="./screenshots/starship.png"></div><sub><i>Starship Demo</i></sub></p>
  <p><div><img src="./screenshots/fastfetch.png"></div><sub><i>Fetch Demo</i></sub></p>
  <p><div><img src="./screenshots/manager_dashboard.png"></div><sub><i>System Manager Demo</i></sub></p>
</div>

</details>

## Why this exists

Arch OS is a side project and it installs the system I use every day, at work and at home, as a project lead and cloud native engineer. It started with Ubuntu, back in 2005.

The two halves are written differently on purpose. Oak is Go, written with AI assistance and reviewed line by line before anything is merged, and it lives in a repository of its own so that anybody can build something like this without inheriting my Arch Linux opinions. The Arch Linux side (Installer, Recovery, shell scripts, YAML) is handwritten and grew out of the Installer that existed before there was a runtime to drive it.

## Credits

Many thanks for these projects and the people behind them!

- Arch Linux
- GNOME
- Bubble Tea by charm

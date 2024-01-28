<h1 align="center">
  <img src="./logo.svg" width="150" height="150"/>
  <p>Arch OS</p>
</h1>

<p align="center"><strong>Run TUI Installer from official <a target="_blank" href="https://archlinux.org/download/">Arch ISO</a></strong></p>

<div align="center">

```
curl -Ls http://arch.webhop.me | bash
```

</div>

<p align="center"><img src="./screenshots/desktop.jpg" /></p>

<div align="center">

**[➜ Open Arch OS Docs](DOCS.md)**

</div>

<p align="center">
This project aims to provide a solid Arch Linux base for desktop usage and an easy and fast to use installer for that. Choose between three variants and install a minimal Arch Linux Distribution optional with automatic housekeeping, Zen Kernel, GNOME as desktop with graphics driver, preinstalled Paru as AUR Helper, enabled MultiLib, Pipewire Audio and some more features...
</p>

<p align="center"><strong>Sole OS on a single disk</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/MAINTAINED-YES-green?style=for-the-badge">
  <img src="https://img.shields.io/badge/LICENSE-MIT-blue?style=for-the-badge">
</p>

<p align="center">
  <strong>Test successful</strong>
  <br>
  <a target="_blank" href="https://www.archlinux.de/releases/2024.01.01">archlinux-2024.01.01-x86_64.iso</a>
</p>

## Core Features

- Zen Kernel (configurable)
- Swap (zram-generator)
- Disk Encryption (optional)
- Systemd Bootloader (auto updated)
- Systemd OOM (out-of-memory killer)
- Network Manager
- SSD Support
- Microcode Support (Intel/AMD)
- Designed as the only OS on the disk
- UEFI only supported
- [Arch OS Bootsplash](https://github.com/murkl/plymouth-theme-arch-os) (optional)

## Base Features

- **+ Core Features**
- AUR Helper (configurable)
- Multilib (optional)
- Missing package suggestion for commands
- Automatic Pacman mirrorlist update (on every startup)
- Pacman automatic cache optimization (weekly)
- Pacman parallel downloads
- Pacman & nano colors
- Preconfigured fish shell (optional)
- Preconfigured neofetch to show system info (optional)
- Preconfigured starship for fancy Shell promt (optional)
- Preconfigured eza as colorful ls replacement (optional)
- Preconfigured bat as colorful man replacement (optional)

## Desktop Features

- **+ Base Features**
- Minimal Vanilla GNOME Desktop + Auto Login
- Graphics Driver & Gamemode (Mesa, Intel i915, NVIDIA, AMD)
- Pipewire Audio (Dolby Atmos supported)
- Flatpak Support + Auto Update (GNOME Software)
- Firmware Update Tool preinstalled
- GNOME Power Profiles Support
- Samba, Networking Protocol Libs, Git, Utils & Codecs included
- Printer Support
- Wayland optimized
- VM Support

## Arch OS Installation

### 1. Prepare bootable USB Device

- Download latest Arch Linux ISO from **[archlinux.org](https://www.archlinux.org/download)** or **[archlinux.de](https://www.archlinux.de/download)**
- Use **[Ventoy](https://www.ventoy.net/en/download.html)** or your prefered iso writer tool to create bootable Device
- Alternatively (Linux only): `sudo dd bs=4M if=archlinux-*.iso of=/dev/sdX status=progress`

### 2. Configure BIOS Settings

- Disable Secure Boot
- Set Boot Mode to UEFI
- Set Real Time Clock to **[UTC](https://time.is/de/UTC)**

### 3. Boot from USB Device

- Load prefered keyboard layout (optional): `loadkeys de`
- Connect to WLAN (optional): `iwctl station wlan0 connect "SSID"`
- **Run Arch OS Installer:**

<div align="center">

```
curl -Ls http://arch.webhop.me | bash
```

<p><img src="./screenshots/installer_01.png" /></p>

<p><b>

[➜ More Screenshots](DOCS.md#screenshots)

</b></p>

</div>

## Usage

For a robust & stable Arch OS experience, install as few additional packages from the official [Arch Repository](https://archlinux.org/packages) or [AUR](https://aur.archlinux.org) as possible. Instead, use [Flatpak](https://flathub.org) or [GNOME Software](https://apps.gnome.org). Furthermore change system files only if absolutely necessary and perform regular package upgrades.

### For Developer

For sandboxed CLI tools or test environment you can try [Distrobox](https://distrobox.it/) or [Toolbox](https://containertoolbx.org) and as container runtime use [Podman](https://podman.io) or [Docker](https://www.docker.com).

### For Gamer

For native **Microsoft Windows Gaming** install [Qemu](https://wiki.archlinux.org/title/QEMU) and enable GPU Passthrough. Then you can use an emulated Microsoft Windows with native GPU access. For quick installation, have a look to this project: [quickpassthrough](https://github.com/HikariKnight/quickpassthrough)

**Note:** Use [gamemode](https://wiki.archlinux.org/title/Gamemode) when playing games from Linux with: `gamemoderun <file>`

### General Commands

```
fetch
```

<img src="screenshots/neofetch.png" />

#### Update system

```
paru -Syu
```

#### Search package

```
paru -Ss <my search string>
```

#### Install package

```
paru -S <my package>
```

#### List installed packages

```
paru -Qe
```

#### Show package info

```
paru -Qi <my package>
```

#### Remove package

```
paru -Rsn <my package>
```

## More Information

**[➜ Open Arch OS Docs](DOCS.md)**

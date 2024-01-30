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
This project aims to provide a solid Arch Linux base for desktop usage and an easy and fast to use installer for that. Choose between 3 Arch OS Variants and install a minimal Arch Linux Distribution optional with automatic housekeeping, Zen Kernel, GNOME as desktop with graphics driver, preinstalled Paru as AUR Helper, enabled MultiLib, Pipewire Audio and some more features...
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

- [Minimal Arch Linux](DOCS.md#minimal-installation) (171 packages)
- Zen Kernel ([configurable](DOCS.md#installation-properties))
- [Swap](DOCS.md#swap) with zram-generator (zstd)
- Disk Encryption (optional)
- Filesystem ext4
- Silent Boot
- [Arch OS Bootsplash](https://github.com/murkl/plymouth-theme-arch-os) (optional)
- Systemd Bootloader (auto updated)
- Systemd OOM (out-of-memory killer)
- Watchdog disabled
- Network Manager
- SSD Support (fstrim)
- Microcode Support (Intel/AMD)
- Sole OS on a single disk (see [Arch OS Docs](DOCS.md#partitions-layout))
- UEFI only supported

## Base Features

- **+ Core Features**
- AUR Helper ([configurable](DOCS.md#installation-properties))
- Multilib (optional)
- [Shell Enhancement](DOCS.md#shell-enhancement)
- Missing package suggestion for commands
- Automatic Pacman mirrorlist update (on every startup)
- Pacman automatic cache optimization (weekly)
- Pacman parallel downloads
- Pacman & nano colors

## Desktop Features

- **+ Base Features**
- Vanilla GNOME Desktop + Auto Login
- [Graphics Driver](DOCS.md#install-graphics-driver-manually) & Gamemode (Mesa, Intel i915, NVIDIA, AMD, ATI)
- [Pipewire Audio](DOCS.md#for-audiophiles) (Dolby Atmos supported)
- Flatpak Support + Auto Update (GNOME Software)
- Firmware Update Tool preinstalled
- GNOME Power Profiles Support
- Samba, Networking Protocol Libs, Git, Utils & Codecs included
- Printer Support (cups)
- Wayland optimized
- [VM Support](DOCS.md#vm-support)

## Arch OS Installation

<div align="center">

<p><img src="./screenshots/installer_01.png" /></p>

<p><b>

[➜ More Screenshots](DOCS.md#screenshots)

</b></p>

</div>

### 1. Prepare bootable USB Device

- Download latest Arch Linux ISO from **[archlinux.org](https://www.archlinux.org/download)** or **[archlinux.de](https://www.archlinux.de/download)**
- Use **[Ventoy](https://www.ventoy.net/en/download.html)** or your prefered iso writer tool to create a bootable USB device
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

</div>

<div align="center">

<p><b>

[➜ See Advanced Installation](DOCS.md#installation-properties)

</b></p>

</div>

## Usage

<div align="center">

<p><img src="screenshots/neofetch.png" /></p>

<p><b>

[➜ See Recommendation](DOCS.md#recommendation)

</b></p>

</div>

### System information

```
fetch
```

### Update system

```
paru -Syu
```

### Search package

```
paru -Ss <my search string>
```

### Install package

```
paru -S <my package>
```

### List installed packages

```
paru -Qe
```

### Show package info

```
paru -Qi <my package>
```

### Remove package

```
paru -Rsn <my package>
```

## More Information

Further information can be found in the documentation.

**[➜ Open Arch OS Docs](DOCS.md)**

<h1 align="center">
  <img src="./logo.svg" width="150" height="150"/>
  <p>Arch OS</p>
</h1>

<p align="center"><strong>Boot from official <a target="_blank" href="https://archlinux.org/download/">Arch ISO</a> and simply run</strong></p>

<div align="center">

```
curl -Ls http://arch.webhop.me | bash
```

<p align="center">
This project aims to provide a robust Arch Linux base for desktop usage, along with an easy-to-use and fast installer. Install a minimal Arch Linux core with optional features such as Automatic Housekeeping, Zen Kernel, GNOME Desktop with Graphics Drivers, preinstalled Paru as AUR Helper, enabled MultiLib, Pipewire Audio, and some more....
</p>

<p><b>

[➜ Open Arch OS Docs](DOCS.md)

</b></p>

</div>

<p align="center"><img src="./screenshots/installer_01.png" /></p>

<div align="center"><p><b>

[➜ More Screenshots](DOCS.md#screenshots)

</b></p></div>

<p align="center">
  <img src="https://img.shields.io/badge/MAINTAINED-YES-green?style=for-the-badge">
  <img src="https://img.shields.io/badge/License-GPL_v2-blue?style=for-the-badge">
</p>

<p align="center">
  <strong>Test successful</strong>
  <br>
  <a target="_blank" href="https://www.archlinux.de/releases/2024.02.01">archlinux-2024.02.01-x86_64.iso</a>
  <br>
  <sub>100% shellcheck approved</sub>
</p>

## Core Features

- [Minimal Arch Linux](DOCS.md#minimal-installation) (171 packages)
- Zen Kernel ([configurable](DOCS.md#installation-properties))
- [Swap](DOCS.md#swap) with zram-generator (zstd)
- Filesystem ext4
- Silent Boot
- Systemd Bootloader (auto updated)
- Systemd OOM (out-of-memory killer)
- Watchdog disabled
- Network Manager
- SSD Support (fstrim)
- Microcode Support (Intel/AMD)
- Sole OS on a single disk (see [Arch OS Docs](DOCS.md#partitions-layout))
- UEFI only supported

## Optional Features

- Vanilla GNOME Desktop + Auto Login
- [Graphics Driver](DOCS.md#install-graphics-driver-manually) (Mesa, Intel i915, NVIDIA, AMD, ATI)
- Wayland optimized
- [Pipewire Audio](DOCS.md#for-audiophiles) (Dolby Atmos supported)
- [Arch OS Bootsplash](https://github.com/murkl/plymouth-theme-arch-os)
- AUR Helper ([configurable](DOCS.md#installation-properties))
- 32 Bit Support (Multilib)
- Disk Encryption
- [Shell Enhancement](DOCS.md#shell-enhancement)
- Missing package suggestion for commands
- Automatic Pacman mirrorlist update (on every startup)
- Pacman automatic cache optimization (weekly)
- Pacman parallel downloads
- Pacman & nano colors
- Flatpak Support + Auto Update (GNOME Software)
- Samba, Networking Protocol Libs, Git, Utils & Codecs included
- GNOME Power Profiles Support
- Printer Support (cups)
- Gamemode preinstalled
- Firmware Update Tool preinstalled
- [VM Support](DOCS.md#vm-support)

## Installing Arch OS

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

```
# Stable
curl -Ls http://arch.webhop.me | bash

# Development
curl -Ls http://arch-dev.webhop.me | bash
```

<div align="center">

**[➜ See Advanced Installation](DOCS.md#installation-properties)**

</div>

## Using Arch OS

<div align="center">

<p><img src="./screenshots/desktop.jpg" /></p>

**[➜ See Recommendation](DOCS.md#recommendation)**

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

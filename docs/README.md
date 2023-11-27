<h1 align="center">
  <img src="./logo.svg" width="150" height="150"/>
  <br>
  Arch OS
</h1>

<p align="center">
  <strong>Run TUI Installer from booted Arch ISO</strong>
</p>

<div align="center">

```
curl -Ls http://arch.webhop.me | bash
```

</div>

<p align="center"><img src="./screenshots/desktop.jpg" /></p>

<p align="center">
This project aims to provide a minimal and solid Arch Linux base for desktop usage and an easy and fast to use installer for that.
Installs a Arch Linux Distribution including GNOME, preinstalled Paru as AUR Helper, enabled MultiLib and some more features. 
</p>

<p align="center"><strong>Sole OS on a single disk</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/MAINTAINED-YES-green?style=for-the-badge">
  <img src="https://img.shields.io/badge/LICENSE-MIT-blue?style=for-the-badge">
</p>

<p align="center">
  <strong>Test successful</strong>
  <br>
  <a target="_blank" href="https://www.archlinux.de/releases/2023.11.01">archlinux-2023.11.01-x86_64.iso</a>
</p>

# Contents

1. [Features](#features)
2. [Installation](#installation)
3. [Documentation](#documentation)

## Features

- 100% TUI Installation
- Installation Properties
- VM Support
- Minimal GNOME Desktop + Autologin (optional)
- Linux Zen Kernel
- Disk Encryption (optional)
- Systemd Bootloader (auto updated)
- Wayland optimized
- Network Manager
- Pipewire Audio (Dolby Atmos supported)
- AUR Helper & Multilib
- Microcode Support
- SSD Support
- GNOME Power Profiles Support
- Firmware Update Tool
- Automatic mirrorlist update (on every startup)
- Missing package suggestion
- Pacman parallel downloads
- Pacman automatic cache optimization (weekly)
- Printer Support
- Pacman & nano colors
- Systemd OOM (out-of-memory killer)
- Networking, Utils & Codecs included
- Installer Error Handling
- Tested in GNOME Boxes
- Shellcheck approved
- [Arch OS Bootsplash](https://github.com/murkl/plymouth-theme-arch-os) (optional)

## Installation

<p><img src="./screenshots/installer.png" /></p>

### 1. Prepare bootable USB Device

- Download latest Arch Linux ISO from **[here](https://www.archlinux.de/download)**
- Show disk info with `lsblk`
- Write to device: `sudo dd bs=4M if=archlinux-*.iso of=/dev/sdX status=progress`
- Alternatively use **[Ventoy](https://www.ventoy.net/en/download.html)**

### 2. Configure BIOS Settings

- Disable Secure Boot
- Set Boot Mode to UEFI
- Set Real Time Clock to **[UTC](https://time.is/de/UTC)**

### 3. Boot from USB Device

- Load prefered keyboard layout (optional): `loadkeys de`
- Connect to WLAN (optional): `iwctl station wlan0 connect "SSID"`
- Run **Arch OS Installer**: `curl -Ls http://arch.webhop.me | bash`
- Installation finished

## Documentation

Open Documentation: **[DOCS.md](DOCS.md)**

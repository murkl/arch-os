<h1 align="center">
  <img src="./logo.svg" width="150" height="150">
  <p>Arch OS</p>
</h1>

<div align="center">

<p><strong>Boot from official <a target="_blank" href="https://archlinux.org/download/">Arch ISO</a> and run</strong></p>

**`curl -Ls bit.ly/arch-os | bash`**

<p><b>

[➜ Step by Step Installation Guide](#installing-arch-os)

</b></p>

<p><img src="./screenshots/installer_start.png"></p>

<p><b>

[➜ More Screenshots](DOCS.md#screenshots)

</b></p>

<p>
This project aims to provide a mostly automized, minimal and robust Arch Linux base, along with an easy-to-use and fast properties-file-based installer with error handling. Install a minimal Arch Linux core with optional features such as GNOME Desktop with Graphics Driver, Automatic Housekeeping, Zen Kernel, Fancy Shell Enhancement, preinstalled Paru as AUR Helper, enabled MultiLib, Pipewire Audio and some more...</p>

<p>
  <img src="https://img.shields.io/badge/MAINTAINED-YES-green?style=for-the-badge">
  <img src="https://img.shields.io/badge/License-GPL_v2-blue?style=for-the-badge">
</p>
<p>
  <strong>Test successful</strong>
  <br>
  <a target="_blank" href="https://www.archlinux.de/releases/2024.11.01">archlinux-2024.11.01-x86_64.iso</a>
  <br>
  <sub>100% shellcheck approved</sub>
</p>

</div>

## Core Features

- [Minimal Arch Linux](DOCS.md#minimal-installation) (~150 packages)
- [Zen Kernel](DOCS.md#advanced-installation) (configurable)
- [Swap](DOCS.md#swap) with zram-generator (zstd)
- [Sole OS](DOCS.md#partitions-layout)
- All-in-One password (encryption, root & user)
- Multilingual Support
- Filesystem ext4
- Silent Boot (optional)
- Systemd Bootloader (auto updated)
- Systemd OOM (out-of-memory killer)
- Pacman parallel downloads & eyecandy (optional)
- Network Manager
- SSD Support (fstrim)
- Microcode Support (Intel & AMD)
- Disabled Watchdog (optional)
- UEFI only supported
- [More Information...](DOCS.md#technical-information)

## Additional Features

- [Arch OS System Manager](DOCS.md#arch-os-manager)
- [Arch OS Core Tweaks](DOCS.md#core-tweaks)
- [Arch OS Shell Enhancement](DOCS.md#shell-enhancement)
- [Arch OS Automatic Housekeeping](DOCS.md#housekeeping)
- [Arch OS Bootsplash](https://github.com/murkl/plymouth-theme-arch-os)
- [AUR Helper](DOCS.md#advanced-installation) (configurable)
- [GNOME Desktop Environment](#desktop-features) (optional with additional packages)
- [Graphics Driver](DOCS.md#install-graphics-driver-manually) (Mesa, Intel i915, NVIDIA, AMD, ATI)
- [VM Support](DOCS.md#vm-support) (optional)
- 32 Bit Support (Multilib)
- Disk Encryption (LUKS2)

## Desktop Features

- [Arch OS Slim Version](DOCS.md#example-installerconf) (GNOME Core Apps only)
- [Pipewire Audio](DOCS.md#for-audiophiles) (Dolby Atmos supported)
- Flatpak Support + Auto Update (GNOME Software)
- Samba, Networking Protocol Libs, Git, Utils & Codecs included
- Wayland optimized
- GNOME Power Profiles Support
- Auto Login enabled
- Printer Support (cups)
- Gamemode preinstalled
- Firmware Update Tool preinstalled

## Properties Presets

Select one of these presets (prompted in the installer) to [install](#installing-arch-os) your individual Arch Linux base.

- **`desktop`** ➜ GNOME Desktop Environment + Graphics Driver + Extras + Core (default)
- **`core`** ➜ Minimal Arch Linux TTY Environment (~150 packages in total)
- **`none`** ➜ All properties are queried (customize)

**Note:** If the `installer.conf` exists in the working dir (auto-detected), all properties are loaded as preset (except the password).

## Installing Arch OS

To install Arch OS, an internet connection is required, as many packages will be downloaded during the installation process.

### 1. Prepare bootable USB Device

- Download latest Arch Linux ISO from **[archlinux.org](https://www.archlinux.org/download)** or **[archlinux.de](https://www.archlinux.de/download)**
- Use **[Ventoy](https://www.ventoy.net/en/download.html)** or your prefered iso writer tool to create a bootable USB device
- Alternatively (Linux only): **[➜ Arch OS Creator](https://github.com/murkl/arch-os-creator)**

### 2. Configure BIOS Settings

- Disable Secure Boot
- Set Boot Mode to UEFI

### 3. Boot from USB Device

- Load prefered keyboard layout (optional): `loadkeys de`
- Connect to WLAN (optional): `iwctl station wlan0 connect 'SSID'`

#### 3.1. Run Arch OS Installer

```
curl -Ls bit.ly/arch-os | bash
```

_Cancel the Arch OS Installer with `CTRL + c`_

**[➜ See Advanced Installation](DOCS.md#advanced-installation)**

## System Maintenance

After installing Arch OS with the default properties preset, most maintenance tasks are performed automatically. However, the following steps must be executed manually on a regular basis:

- Regularly upgrade your system packages (Pacman/AUR & Flatpak)
- Regularly read the **[Arch Linux News](https://www.archlinux.org/news)** (preferably before upgrading your system)
- Regularly check & merge new configurations with `pacdiff` (preferably after each system upgrade)
- Consult the **[Arch Linux Wiki](https://wiki.archlinux.org)** (if you need help)

To streamline this process, you can use the preinstalled **[➜ Arch OS Manager](https://github.com/murkl/arch-os-manager)**

## More Information

Further information can be found in the documentation.

**[➜ Open Arch OS Docs](DOCS.md)**

<div align="center">
  <div><img src="./screenshots/desktop_demo.jpg"></div>
  <sub><i>Arch OS Desktop Demo</i></sub>
</div>

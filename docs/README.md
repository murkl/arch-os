<h1 align="center">
  <img src="./logo.svg" width="150" height="150"/>
  <p>Arch OS</p>
</h1>

<div align="center">

<p><strong>Boot from official <a target="_blank" href="https://archlinux.org/download/">Arch ISO</a> and run</strong></p>

**`curl -Ls bit.ly/arch-os | bash`**

<p><b>

[➜ Open Arch OS Docs](DOCS.md)

</b></p>


<p><img src="./screenshots/installer_01.png" /></p>

<p><b>

[➜ More Screenshots](DOCS.md#screenshots)

</b></p>

<p>
This project aims to provide a robust Arch Linux base for desktop usage, along with an easy-to-use and fast installer with error handling. Install a minimal Arch Linux core with optional features such as Automatic Housekeeping, Zen Kernel, GNOME Desktop with Graphics Driver, preinstalled Paru as AUR Helper, enabled MultiLib, Pipewire Audio, and some more....
</p>

<p>
  <img src="https://img.shields.io/badge/MAINTAINED-YES-green?style=for-the-badge">
  <img src="https://img.shields.io/badge/License-GPL_v2-blue?style=for-the-badge">
</p>

<p>
  <strong>Test successful</strong>
  <br>
  <a target="_blank" href="https://www.archlinux.de/releases/2024.02.01">archlinux-2024.02.01-x86_64.iso</a>
  <br>
  <sub>100% shellcheck approved</sub>
</p>

</div>

## Arch OS Core Features

- [Minimal Arch Linux](DOCS.md#minimal-installation) (149 packages)
- Zen Kernel ([configurable](DOCS.md#advanced-installation))
- [Swap](DOCS.md#swap) with zram-generator (zstd)
- Filesystem ext4
- Silent Boot
- Systemd Bootloader (auto updated)
- Systemd OOM (out-of-memory killer)
- Pacman parallel downloads & eyecandy
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
- AUR Helper ([configurable](DOCS.md#advanced-installation))
- 32 Bit Support (Multilib)
- Disk Encryption
- [Shell Enhancement](DOCS.md#shell-enhancement)
- Automatic Pacman mirrorlist update (see [Housekeeping](DOCS.md#housekeeping))
- Pacman automatic cache optimization (weekly)
- Missing package suggestion for commands
- Flatpak Support + Auto Update (GNOME Software)
- Samba, Networking Protocol Libs, Git, Utils & Codecs included
- GNOME Power Profiles Support
- Printer Support (cups)
- Gamemode preinstalled (desktop)
- Firmware Update Tool preinstalled (desktop)
- [VM Support](DOCS.md#vm-support)
- [Arch OS Bootsplash](https://github.com/murkl/plymouth-theme-arch-os)
- [Arch OS App](https://github.com/murkl/arch-os-app)

## Installing Arch OS

**[➜ See Advanced Installation](DOCS.md#advanced-installation)**

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
- Connect to WLAN (optional): `iwctl station wlan0 connect 'SSID'`
- **Run Arch OS Installer: `curl -Ls  bit.ly/arch-os | bash`**

## Using Arch OS

<div align="center">

<p><img src="./screenshots/desktop_01.jpg" /></p>

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

<div align="center"><sub>Developed with ❤ in Germany</sub></div>

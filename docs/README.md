<div align="center">

<img src="banner.png" alt="Arch OS">

<p>Install <b>Arch Linux</b> with <b>GNOME</b> or the <b>text&nbsp;console</b>, plus <b>Recovery</b> and <b>System&nbsp;Manager</b>.</p>

<p><a href="https://github.com/murkl/arch-os/releases/latest"><img src="download.svg" alt="Download the latest ISO, for x86_64 with UEFI"></a></p>

<p>
  <sub><b>Requirements</b></sub>
  <br>
  <picture><source media="(prefers-color-scheme: dark)" srcset="requirements/core-dark.svg"><img src="requirements/core-light.svg" alt="Core: Text console, 2 GiB memory, 16 GiB disk"></picture>
  <picture><source media="(prefers-color-scheme: dark)" srcset="requirements/desktop-dark.svg"><img src="requirements/desktop-light.svg" alt="Desktop: GNOME on Wayland, 4 GiB memory, 32 GiB disk"></picture>
</p>

**[➜ Reference](REFERENCE.md)** · **[➜ Contributing](CONTRIBUTING.md)** · **[➜ Telegram](https://t.me/archos_community)**

<p>
  <a href="https://github.com/murkl/arch-os/releases/latest"><img src="https://img.shields.io/static/v1?label=release&message=2.0.0&color=5e81ac&style=flat-square" alt="Latest release"></a> <!-- x-release-please-version -->
  <a href="../LICENSE"><img src="https://img.shields.io/static/v1?label=license&message=GPL-3.0&color=5e81ac&style=flat-square" alt="License"></a>
</p>

</div>

## Features

- Minimal base: linux-zen, btrfs, systemd-boot
- Disk encryption, Secure Boot with own keys
- One password for disk, login and keyring
- Btrfs snapshot before every package change
- Recovery partition with rollback and self-update
- Recovery in boot menu, firmware menu and app grid
- Automatic fallback: fallback image, then Recovery
- GNOME on Wayland or text console
- Drivers and VM guest tools detected
- Flatpak with GNOME Software or Bazaar
- Browser, backup app and text editor of choice
- AUR helper, 32-bit support, containers, firewall, SSH
- File sharing with Windows and macOS
- Zram, OOM protection, [tuned defaults](REFERENCE.md#tuning)
- Ranked mirrors, trimmed package cache, disk health monitoring
- Works offline until the next update
- [Bootsplash](https://github.com/murkl/plymouth-theme-arch-os), [System Manager](https://github.com/murkl/arch-os-manager), [Shell Enhancement](https://github.com/murkl/starship-theme-arch-os)
- Keyboard, time zone and mirrors follow the language
- Resumable installation, shareable answers
- English and German, [Adding a Language](CONTRIBUTING.md#adding-a-language)

## Installation

1. Write the **[latest ISO](https://github.com/murkl/arch-os/releases/latest)** to a USB stick, for example with **[Ventoy](https://www.ventoy.net)** or **[balenaEtcher](https://etcher.balena.io)**
2. Set the firmware to UEFI, Secure Boot off
3. Boot the USB stick, choose **Core** or **Desktop**, then **Install now**. Needs internet by cable or Wi-Fi
4. After the first reboot, **[turn Secure Boot on](REFERENCE.md#turning-it-on)**

<p align="center"><img src="screenshots/installer.png" width="100%" alt="Dashboard with every answer"><br><sub><b>Dashboard</b> · every answer prefilled</sub></p>

<p align="center"><img src="screenshots/installing.png" width="100%" alt="Installation in progress"><br><sub><b>Installation</b> · step by step</sub></p>

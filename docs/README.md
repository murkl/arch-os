<div align="center">

<img src="banner.png" alt="Arch OS">

<p>Install <b>Arch Linux</b> with ease, for a <b>GNOME</b>&nbsp;desktop or the <b>text&nbsp;console</b>, with an optional <b>Recovery</b> and <b>System&nbsp;Manager</b>.</p>

<p><a href="https://github.com/murkl/arch-os/releases/latest"><img src="download.svg" alt="Download the latest ISO, for x86_64 with UEFI"></a></p>

<p>
  <sub><b>Requirements</b></sub>
  <br>
  <picture><source media="(prefers-color-scheme: dark)" srcset="requirements/core-dark.svg"><img src="requirements/core-light.svg" alt="Core: Text console, 2 GiB memory, 16 GiB disk"></picture>
  <picture><source media="(prefers-color-scheme: dark)" srcset="requirements/desktop-dark.svg"><img src="requirements/desktop-light.svg" alt="Desktop: GNOME on Wayland, 4 GiB memory, 32 GiB disk"></picture>
</p>

**[➜ Reference](REFERENCE.md)** · **[➜ Contributing](CONTRIBUTING.md)** · **[➜ Telegram](https://t.me/archos_community)**

<p>
  <a href="https://github.com/murkl/arch-os/releases/latest"><img src="https://img.shields.io/github/v/release/murkl/arch-os?style=flat-square&label=release&color=5e81ac" alt="Latest release"></a>
  <a href="../LICENSE"><img src="https://img.shields.io/github/license/murkl/arch-os?style=flat-square&color=5e81ac" alt="License"></a>
</p>

</div>

## Features

- Minimal Arch Linux base: linux-zen, btrfs, systemd-boot
- Disk encryption and Secure Boot with your own keys
- One password unlocks the disk, logs in to GNOME and opens the keyring
- Btrfs snapshots before every package change
- Recovery on its own partition, rollback included, updates itself
- Recovery from the boot menu, the firmware and the app grid
- Falls back on its own: fallback image, then the Recovery
- GNOME on Wayland or a text console, drivers and guest tools detected
- Flatpak from GNOME Software, or Bazaar with GNOME Firmware
- Browser, backup app and text editor of your choice
- AUR helper, 32-bit support, containers, firewall, SSH
- File sharing with Windows and macOS
- Zram, an out-of-memory guard and [tuned defaults](REFERENCE.md#tuning) for older machines
- Mirrors ranked, package cache trimmed, disks checked, quiet while offline
- [Bootsplash](https://github.com/murkl/plymouth-theme-arch-os), [System Manager](https://github.com/murkl/arch-os-manager), [Shell Enhancement](https://github.com/murkl/starship-theme-arch-os)
- Asks only what it cannot work out: keyboard, time zone and mirrors follow the language
- Installer resumes after an interruption, answers shareable as a code
- English and German, [Adding a Language](CONTRIBUTING.md#adding-a-language)

## Installation

1. Write the **[latest ISO](https://github.com/murkl/arch-os/releases/latest)** to a USB stick with **[Ventoy](https://www.ventoy.net)** or **[balenaEtcher](https://etcher.balena.io)**
2. Set the firmware to UEFI and turn Secure Boot off
3. Boot from the USB stick, choose a profile (**Core** or **Desktop**), then **Install now**. It needs the internet, by cable or Wi-Fi
4. After the installation and the first reboot, **[turn Secure Boot on](REFERENCE.md#turning-it-on)**

<p align="center"><img src="screenshots/installer.png" width="100%" alt="The dashboard: every answer on one page, grouped and changeable before the start"><br><sub><b>Dashboard</b> · every answer prefilled and changeable</sub></p>

<p align="center"><img src="screenshots/installing.png" width="100%" alt="The installation, each step checked off as it runs"><br><sub><b>Installation</b> · each step as it runs</sub></p>

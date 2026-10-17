<div align="center">

<img src="banner.png" alt="Arch OS: install Arch Linux with ease, as a desktop or a TTY system, with an Installer and a Recovery on one bootable image">

<p>
  <img src="https://img.shields.io/github/v/release/murkl/arch-os?style=for-the-badge&label=RELEASE&color=1793d1" alt="">
  <img src="https://img.shields.io/badge/License-GPL_3.0-blue?style=for-the-badge" alt="">
</p>

<p><b>Install Arch Linux with ease, as a desktop or a TTY system.</b></p>

<p><a href="https://github.com/murkl/arch-os/releases/latest"><img src="download.svg" alt="Download the latest ISO, for x86_64 with UEFI"></a></p>

<p>
  <picture><source media="(prefers-color-scheme: dark)" srcset="requirements/core-dark.svg"><img src="requirements/core-light.svg" alt="Core (Text console): 2 GiB memory, 16 GiB disk"></picture>
  <picture><source media="(prefers-color-scheme: dark)" srcset="requirements/desktop-dark.svg"><img src="requirements/desktop-light.svg" alt="Desktop (GNOME on Wayland): 4 GiB memory, 32 GiB disk"></picture>
</p>

**[➜ Reference](REFERENCE.md)** · **[➜ Telegram](https://t.me/archos_community)**

</div>

## Features

- Minimal Arch Linux base: linux-zen, btrfs, systemd-boot
- Disk encryption and Secure Boot with your own keys
- Btrfs snapshots before every package change
- Recovery on its own partition, rollback included
- Falls back to the previous image, then to the Recovery
- GNOME on Wayland or a text console, graphics drivers detected
- Desktop extras or a slim GNOME, Flatpak
- Browser, backup app and text editor of your choice
- AUR helper, 32-bit support, containers, firewall, SSH
- Zram, an out-of-memory guard and tuned defaults for older machines
- Works offline: no timer fails without internet
- [Bootsplash](https://github.com/murkl/plymouth-theme-arch-os), [Arch OS Manager](https://github.com/murkl/arch-os-manager), Shell Enhancement
- English and German

## Installation

1. Write the **[latest ISO](https://github.com/murkl/arch-os/releases/latest)** to a USB device with any ISO writer, or on any Linux:
   ```sh
   curl -Ls https://bit.ly/archos | bash
   ```
2. Set the firmware to UEFI and switch Secure Boot off
3. Boot the USB device, choose the **Installer** and a starting point, then **Start**. It needs the internet, by cable or Wi-Fi
4. After the first start, **[switch Secure Boot on](REFERENCE.md#switching-it-on)**

<p align="center"><img src="screenshots/installer.png" width="100%" alt="Setup: every answer on one page, grouped and changeable before the start"><br><sub><b>Setup</b> · every answer before the start</sub></p>

<p align="center"><img src="screenshots/installing.png" width="100%" alt="The installation, each step checked off as it runs"><br><sub><b>Installation</b> · each step as it runs</sub></p>

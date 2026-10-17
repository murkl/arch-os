<div align="center">

<img src="banner.png" alt="Arch OS">

<h3>Install Arch Linux with ease, as a desktop or a TTY system, with a Recovery and a&nbsp;System&nbsp;Manager.</h3>

<p>
  <a href="https://github.com/murkl/arch-os/releases/latest"><img src="download.svg" alt="Download the latest ISO, for x86_64 with UEFI"></a>
  <br>
  <picture><source media="(prefers-color-scheme: dark)" srcset="requirements/core-dark.svg"><img src="requirements/core-light.svg" alt="Core (Text console): 2 GiB memory, 16 GiB disk"></picture>
  <picture><source media="(prefers-color-scheme: dark)" srcset="requirements/desktop-dark.svg"><img src="requirements/desktop-light.svg" alt="Desktop (GNOME on Wayland): 4 GiB memory, 32 GiB disk"></picture>
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
- Btrfs snapshots before every package change
- Recovery on its own partition, rollback included
- Falls back on its own: fallback image, then the Recovery
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
3. Boot the USB device, choose a starting point, then **Start**. It needs the internet, by cable or Wi-Fi
4. After the first start, **[switch Secure Boot on](REFERENCE.md#switching-it-on)**

<p align="center"><img src="screenshots/installer.png" width="100%" alt="Setup: every answer on one page, grouped and changeable before the start"><br><sub><b>Setup</b> · every answer prefilled and changeable</sub></p>

<p align="center"><img src="screenshots/installing.png" width="100%" alt="The installation, each step checked off as it runs"><br><sub><b>Installation</b> · each step as it runs</sub></p>

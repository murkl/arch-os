<div align="center">

<img src="banner.png" alt="Arch OS: install Arch Linux with ease, as a desktop or a TTY system, with an Installer and a Recovery on one bootable image">

<p>
  <img src="https://img.shields.io/github/v/release/murkl/arch-os?style=for-the-badge&label=RELEASE&color=1793d1" alt="">
  <img src="https://img.shields.io/badge/License-GPL_3.0-blue?style=for-the-badge" alt="">
</p>

<p><b>Install Arch Linux with ease, as a desktop or a TTY system.</b></p>

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

## Requirements

| | Core | Desktop |
| --- | --- | --- |
| Processor | x86_64 with UEFI | x86_64 with UEFI |
| Memory | 2 GiB | 4 GiB |
| Disk | 16 GiB | 32 GiB |

## Installation

1. Write the **[latest ISO](https://github.com/murkl/arch-os/releases/latest)** to a USB device with any ISO writer, or on any Linux:
   ```sh
   curl -Ls https://bit.ly/archos | bash
   ```
2. Set the firmware to UEFI and switch Secure Boot off
3. Boot the USB device, choose the **Installer** and a starting point, then **Start**. It needs the internet, by cable or Wi-Fi
4. After the first start, **[switch Secure Boot on](REFERENCE.md#switching-it-on)**

<img src="screenshots/setup.png" width="720" alt="The Installer's starting points: Desktop, Core, or a shared configuration">

**[➜ Reference](REFERENCE.md)** · **[➜ t.me/archos_community](https://t.me/archos_community)**

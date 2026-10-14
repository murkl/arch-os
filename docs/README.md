<div align="center">

<img src="banner.png" alt="Arch OS: install Arch Linux with ease, as a desktop or a TTY system, with an Installer and a Recovery on one bootable image">

<p>
  <img src="https://img.shields.io/github/v/release/murkl/arch-os?style=for-the-badge&label=RELEASE&color=1793d1" alt="">
  <img src="https://img.shields.io/badge/License-GPL_3.0-blue?style=for-the-badge" alt="">
  <img src="https://img.shields.io/badge/UEFI-x86__64-2e3440?style=for-the-badge" alt="">
</p>

<p><b>Install Arch Linux with ease, as a desktop or a TTY system.</b></p>

<p>Boot the <b><a href="https://github.com/murkl/arch-os/releases/latest">Arch OS ISO</a></b> and the Installer starts by itself. On a booted <a href="https://archlinux.org/download/">Arch Linux ISO</a>, the same command installs or repairs. On any other Linux, it writes the ISO to a USB device.</p>

**`curl -Ls https://bit.ly/archos | bash`**

<p><b>

[➜ Installation](#installation) · [➜ Screenshots](#screenshots) · [➜ Reference](REFERENCE.md) · [➜ Contributing](CONTRIBUTING.md) · [➜ t.me/archos_community](https://t.me/archos_community)

</b></p>

</div>

## Features

- Minimal Arch Linux base, UEFI only: linux-zen, btrfs, systemd-boot
- Disk encryption (LUKS2) and Secure Boot with your own keys
- One password for disk and account, or a separate disk password for a shared machine
- Btrfs snapshots before every package change
- Recovery on its own partition, rollback included
- Falls back to the previous image, then to the Recovery, when a start fails
- GNOME on Wayland or a bare text console, graphics drivers detected
- Desktop extras or a slim GNOME, Flatpak
- Browser and backup app of your choice
- Zram, fstrim, microcode, NetworkManager, mirrors ranked by country
- AUR helper, 32-bit support, containers, firewall, SSH, housekeeping
- Works offline: no timer fails without internet
- Text editor of your choice: nano, vim, neovim, micro or helix
- [Bootsplash](https://github.com/murkl/plymouth-theme-arch-os), [Arch OS Manager](https://github.com/murkl/arch-os-manager), Shell Enhancement (zsh)
- Create boot medium on any Linux machine
- Wi-Fi in the Installer and the Recovery
- Virtual machine guest tools, GNOME Boxes ready to install
- Starting points **Core** and **Desktop**, or a shared configuration
- English and German interface
- Tuned defaults, see the **[➜ Reference](REFERENCE.md)**

## Installation

You need an internet connection: a cable, or a Wi-Fi network joined in the Installer.

### 1. Prepare a USB Device

- Download the latest ISO from **[the release page](https://github.com/murkl/arch-os/releases/latest)** and write it with **[Ventoy](https://www.ventoy.net/en/download.html)** or any ISO writer
- Or let **Create boot medium** do it on any Linux machine:

```
curl -Ls https://bit.ly/archos | bash
```

**Note:** _`gh attestation verify arch-os-<version>-x86_64.iso -R murkl/arch-os` shows which run built a download._

### 2. Set Up the Firmware

- Boot mode: UEFI
- Secure Boot: off for now, see **[step 4](#4-switch-secure-boot-on)**

### 3. Install

Boot from the USB device. Arch OS starts and asks for your language first:

<p><img src="screenshots/welcome.png" alt="The welcome page, asking for the language"></p>

Choose the **Installer** and a starting point:

<p><img src="screenshots/setup.png" alt="The page with the starting points"></p>

| Starting point | What you get |
| --- | --- |
| **Core** | A minimal Arch Linux on the text console |
| **Desktop** | The Core with GNOME |

The Installer then asks for your account, region and disk. You can change every answer in **Setup**. **Start** installs.

### 4. Switch Secure Boot On

Only if you left **Secure Boot** on in **Setup**: switch it on in the firmware after the first start. **[➜ Switching It On](REFERENCE.md#switching-it-on)**

## Recovery

<p><img src="screenshots/recovery.png" alt="The Recovery, opening an installed system"></p>

An installation has a Recovery on its own partition, and the ISO has one too. Hold **space** while the machine starts and choose **Arch OS Recovery**, or open **Recovery** from the applications.

- Unlocks and mounts the system at `/mnt`
- Rolls back to a Btrfs snapshot
- Rebuilds the kernel images from the package cache
- Opens a shell inside the system
- Updates itself within its release series

**[➜ The Recovery](REFERENCE.md#the-recovery)**

## Maintenance

<p><img src="screenshots/manager_menu.png" alt="The Arch OS Manager"></p>

The **[Arch OS Manager](https://github.com/murkl/arch-os-manager)** does most of it. By hand:

- Read the **[Arch Linux News](https://www.archlinux.org/news)** before you upgrade
- Roll back with the **[Recovery](#recovery)**: **[➜ Rolling Back](REFERENCE.md#rolling-back)**
- Look things up in the **[Arch Linux Wiki](https://wiki.archlinux.org)**

<details>

<summary><h2 style="display: inline;" id="screenshots">Screenshots</h2></summary>

<div align="center">
  <p><div><img src="screenshots/welcome.png"></div><sub><i>Welcome</i></sub></p>
  <p><div><img src="screenshots/installing.png"></div><sub><i>Installer</i></sub></p>
  <p><div><img src="screenshots/bootsplash.png"></div><sub><i>Bootsplash</i></sub></p>
  <p><div><img src="screenshots/starship.png"></div><sub><i>Shell Enhancement</i></sub></p>
  <p><div><img src="screenshots/fastfetch.png"></div><sub><i>Fetch</i></sub></p>
  <p><div><img src="screenshots/manager_dashboard.png"></div><sub><i>Arch OS Manager</i></sub></p>
</div>

</details>

## Development

| Part | What it does |
| --- | --- |
| **[`oak`](https://github.com/murkl/oak)** | The runtime: draws the interface, asks, runs the shell |
| **[`modules/installer`](../modules/installer)** | Installs Arch Linux |
| **[`modules/recovery`](../modules/recovery)** | Repairs an installation |
| **[`modules/imager`](../modules/imager)** | Writes the boot medium |
| **[`iso`](../iso)** | Builds the ISO and the Recovery image |

Oak holds nothing specific to Arch Linux. A module is YAML, with shell scripts beside it and shared functions in `oak.sh`.

**[➜ Reference](REFERENCE.md)** · **[➜ Changelog](../CHANGELOG.md)** · **[➜ Contributing](CONTRIBUTING.md)**

## License

GPL-3.0. See **[LICENSE](../LICENSE)**.

## Credits

- **[Arch Linux](https://archlinux.org)**
- **[GNOME](https://www.gnome.org)**
- **[Oak](https://github.com/murkl/oak)**

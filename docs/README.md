<div align="center">
   <h1>Arch Linux Distro</h1>
   <p><img src="./screenshots/desktop.jpg" /></p>
   <p>Minimal Arch Linux Distribution with GNOME, preinstalled Paru as AUR Helper and enabled MultiLib.</p>
   <p>
      <img src="https://img.shields.io/badge/MAINTAINED-YES-green?style=for-the-badge">
      <img src="https://img.shields.io/badge/LICENSE-MIT-blue?style=for-the-badge">
   </p>
</div>

# Contents

1. [Features](#features)
2. [Installation](#step-by-step-installation)
3. [Graphics Driver](#graphics-driver)
4. [Desktop Customization](#desktop-customization)
5. [Rescue & Recovery](#rescue--recovery)
6. [Information](#technical-info)

## Features

- 100% TUI Installation
- LTS Kernel
- Systemd Bootloader
- GNOME Desktop (optional)
- Disk Encryption (optional)
- Network Manager
- AUR Helper & Multilib
- Reflector Service
- Pacman Parallel Downloads
- Tested in GNOME Boxes
- **[Bootsplash](https://github.com/murkl/plymouth-theme-arch-elegant)**

## Step by Step Installation

### 1. Prepare bootable USB Device

- Download latest Arch Linux ISO from **[here](https://www.archlinux.de/download)**
- Write to device: `dd bs=4M if=archlinux-*.iso of=/dev/sdX status=progress`
- Alternatively use **[Etcher](https://www.balena.io/etcher)**

### 2. Configure BIOS Settings

- Disable Secure Boot
- Set Boot Mode to UEFI
- Set Real Time Clock to **[UTC](https://time.is/de/UTC)**

### 3. Boot from USB Device

- Load Keyboard Layout: `loadkeys de-latin1` (use prefered language)
- Connect to WLAN (optional), run `iwctl` and type into console: `station wlan0 connect "SSID"` and `exit`
- **Run Installer with**

```
curl -Ls http://arch.webhop.me | bash
```

<p><img src="./screenshots/installer.png" /></p>

### Default Properties

If the file `default.conf` exists, it will sourced automatically by the `installer.sh` script and the values will set as defaults for Arch Linux installation setup menu.

#### Examples of `default.conf`

```
ARCH_HOSTNAME="virt"
ARCH_USERNAME="moritz"
ARCH_PASSWORD="secret"
ARCH_DISK="/dev/vda"
ARCH_BOOT_PARTITION="/dev/vda1"
ARCH_ROOT_PARTITION="/dev/vda2"
ARCH_ENCRYPTION_ENABLED="true"
ARCH_SWAP_SIZE="8"
ARCH_GNOME="true"
```

#### Add Language

Add this properties to `language.conf` (modify with prefered values):

```
ARCH_LANGUAGE="my-custom-lang"
ARCH_TIMEZONE="Europe/Berlin"
ARCH_LOCALE_LANG="de_DE.UTF-8"
ARCH_LOCALE_GEN_LIST=("de_DE.UTF-8 UTF-8" "de_DE ISO-8859-1")
ARCH_VCONSOLE_KEYMAP="de-latin1-nodeadkeys"
ARCH_VCONSOLE_FONT="eurlatgr"
ARCH_KEYBOARD_LAYOUT="de"
ARCH_KEYBOARD_VARIANT="nodeadkeys"
```

## Graphics Driver

_Use this driver script only after a fresh installation of Arch Linux!_

1. Install Arch Linux
2. Reboot
3. Execute this commands from fresh installed Arch Linux:

```
git clone https://github.com/murkl/arch-distro
cd arch-distro/scripts
./graphics-driver.sh
```

### Manual Installation

- [Intel HD](https://wiki.archlinux.org/title/Intel_graphics#Installation)
- [NVIDIA](https://wiki.archlinux.org/title/NVIDIA#Installation)
- [NVIDIA Optimus](https://wiki.archlinux.org/title/NVIDIA_Optimus#Use_NVIDIA_graphics_only)
- [AMD](https://wiki.archlinux.org/title/AMDGPU#Installation)
- [ATI Legacy](https://wiki.archlinux.org/title/ATI#Installation)

## Desktop Customization

These customizations are not included in `installer.sh` and can be installed optionally after Arch Linux installation.

- Icon Theme: https://github.com/vinceliuice/Tela-icon-theme
- Cursor Theme: https://github.com/alvatip/Nordzy-icon
- Firefox Theme: https://github.com/rafaelmardojai/firefox-gnome-theme
- Libadwaita GTK Theme: https://github.com/lassekongo83/adw-gtk3
- Libadwaita GTK Colors: https://github.com/lassekongo83/adw-colors
- Libadwaita Customization Tool: https://github.com/GradienceTeam/Gradience

## GNOME Shell Extensions

- https://extensions.gnome.org/extension/1010/archlinux-updates-indicator/
- https://extensions.gnome.org/extension/1160/dash-to-panel/
- https://extensions.gnome.org/extension/3843/just-perfection/
- https://extensions.gnome.org/extension/4245/gesture-improvements/

### Additional Extensions

- https://extensions.gnome.org/extension/615/appindicator-support/
- https://extensions.gnome.org/extension/19/user-themes/
- https://extensions.gnome.org/extension/3193/blur-my-shell/
- https://extensions.gnome.org/extension/5237/rounded-window-corners/
- https://extensions.gnome.org/extension/3733/tiling-assistant/

## Rescue & Recovery

If you need to rescue your Arch Linux in case of a crash, **boot from a USB device** and follow these instructions.

### 1. Disk Information

- Show disk info: `lsblk`
  - Example Disk: `/dev/sda`
  - Example Boot: `/dev/sda1`
  - Example Root: `/dev/sda2`

**Note:** _You may have to replace `/dev/sda` with your own disk_

### 2. Mount

- Create mount dir: `mkdir -p /mnt/boot`
- Mount root partition
  - a) Encryption enabled
    - `cryptsetup open /dev/sda2 cryptroot`
    - `mount /dev/mapper/cryptroot /mnt`
  - b) Encryption disabled
    - `mount /dev/sda2 /mnt`
- Mount boot partition: `mount /dev/sda1 /mnt/boot`

### 3. Chroot

- Enter chroot: `arch-chroot /mnt`
- _Fix your Arch Linux..._
- Exit: `exit`

## Technical Info

<p><img src="screenshots/neofetch.png" /></p>

### Packages

This packages will be installed during minimal Arch without GNOME installation (178 packages in total):

```
base base-devel linux-lts linux-firmware networkmanager pacman-contrib reflector git nano bash-completion pkgfile [microcode_pkg]
```

### Services

This services will be enabled during minimal Arch without GNOME installation:

```
NetworkManager systemd-timesyncd.service reflector.service paccache.timer fstrim.timer pkgfile-update.timer
```

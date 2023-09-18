<div align="center">
  <h1>Arch Vanilla Linux Distribution</h1>
  <p><b style="font-size: 14pt">Run TUI Installer within the booted Arch ISO:</b></p>

```
curl -Ls http://arch.webhop.me | bash
```

  <p><img src="./screenshots/desktop.jpg" /></p>
  <p>Minimal Arch Linux Distribution with GNOME Vanilla, preinstalled Paru as AUR Helper, enabled MultiLib and some more features.</p>
  <p>
    <img src="https://img.shields.io/badge/MAINTAINED-YES-green?style=for-the-badge">
    <img src="https://img.shields.io/badge/LICENSE-MIT-blue?style=for-the-badge">
  </p>
</div>

# Contents

1. [Features](#features)
2. [Installation](#step-by-step-installation)
3. [Graphics Driver](#graphics-driver)
4. [Recommendations](#recommendations)
5. [Desktop Customization](#desktop-customization)
6. [Rescue & Recovery](#rescue--recovery)
7. [Information](#technical-info)

## Features

- 100% TUI Installation
- VM Support
- Systemd Bootloader (auto updated)
- Minimal GNOME Desktop (optional)
- Disk Encryption (optional)
- Network Manager
- Pipewire Audio
- AUR Helper & Multilib
- Microcode Support
- SSD Support
- Automatic mirrorlist update
- Missing package suggestion
- Pacman parallel downloads
- Pacman automatic cache optimization
- Printer Support
- Pacman & nano colors
- Networking, Utils & Codecs included
- Wayland optimized
- Installer Error Handling
- Tested in GNOME Boxes
- Shellcheck approved
- **[Bootsplash](https://github.com/murkl/plymouth-theme-arch-elegant)**

## Step by Step Installation

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

- Load Keyboard Layout: `loadkeys de-latin1` (use prefered language)
- Connect to WLAN (optional), run `iwctl` and type into console: `station wlan0 connect "SSID"` and `exit`
- Run **Arch Vanilla Installer** with

```
curl -Ls http://arch.webhop.me | bash
```

- Boot new Arch Linux with `reboot`
- **Arch Vanilla Installation finished**

<p><img src="./screenshots/installer.png" /></p>

### Installation Properties (optional)

```
├─ ./installer.sh (path where installer.sh is executed)
├─ ./default.conf (create this file manually)
├─ ./language.conf (create this file manually)
```

If the file `default.conf` exists in the same dir as `installer.sh`, it will sourced automatically by the `installer.sh` script and the values will set as defaults for Arch Linux installation setup menu.

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

#### Add Custom Language

If you want to install Arch with a custom language, create `language.conf` in the same dir as `installer.sh` and add this properties (modify with prefered values):

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

_Use this driver install script only **after** a fresh installation of Arch Linux!_

1. [Install Arch Linux](#step-by-step-installation)
2. Reboot
3. Execute this commands from fresh installed Arch Linux:

```
git clone https://github.com/murkl/arch-distro
cd arch-distro/scripts
./driver.sh
```

### Manual Installation

- [Intel HD](https://wiki.archlinux.org/title/Intel_graphics#Installation)
- [NVIDIA](https://wiki.archlinux.org/title/NVIDIA#Installation)
- [NVIDIA Optimus](https://wiki.archlinux.org/title/NVIDIA_Optimus#Use_NVIDIA_graphics_only)
- [AMD](https://wiki.archlinux.org/title/AMDGPU#Installation)
- [ATI Legacy](https://wiki.archlinux.org/title/ATI#Installation)

## Recommendations

For a stable Arch Linux experience, install as few additional packages from the main repository or AUR as possible. Instead, use Flatpak or Distrobox/Toolbox (Podman/Docker). Furthermore change system files only if absolutely necessary. And perform regular updates with `paru -Syu`

### Additional Optimization

- Install [preload](https://wiki.archlinux.org/title/Preload) (start the service after installation: `sudo systemctl enable preload`)
- Install [mutter-performance](https://aur.archlinux.org/packages/mutter-performance) (great on Intel Graphics with Wayland)
- Use [downgrade](https://aur.archlinux.org/packages/downgrade) when you need to downgrade a package
- Use [starship](https://starship.rs/) for fancy Bash promt
- Use [exa](https://archlinux.org/packages/extra/x86_64/exa/) as colorful `ls` replacement
- Use [bat](https://archlinux.org/packages/extra/x86_64/bat/) as colorful `man` replacement
- Use [gamemode](https://wiki.archlinux.org/title/Gamemode) when playing games

## Desktop Customization

These customizations are not included in `installer.sh` and can be installed optionally after Arch Linux installation.

- Icon Theme: https://github.com/vinceliuice/Tela-icon-theme
- Cursor Theme: https://github.com/alvatip/Nordzy-cursors
- Desktop Font: https://archlinux.org/packages/extra/any/inter-font/
- Firefox Theme: https://github.com/rafaelmardojai/firefox-gnome-theme
- Nautilus Folder Color: https://aur.archlinux.org/packages/folder-color-nautilus
- Libadwaita GTK Theme: https://github.com/lassekongo83/adw-gtk3
- Libadwaita GTK Colors (optional): https://github.com/lassekongo83/adw-colors
- Libadwaita Customization Tool (optional): https://github.com/GradienceTeam/Gradience

### GNOME Shell Extensions (recommended)

- https://extensions.gnome.org/extension/3843/just-perfection/
- https://extensions.gnome.org/extension/5237/rounded-window-corners/
- https://extensions.gnome.org/extension/3193/blur-my-shell/

### GNOME Shell Extensions (optional)

- https://extensions.gnome.org/extension/1160/dash-to-panel/
- https://extensions.gnome.org/extension/1010/archlinux-updates-indicator/
- https://extensions.gnome.org/extension/615/appindicator-support/
- https://extensions.gnome.org/extension/277/impatience/
- https://extensions.gnome.org/extension/19/user-themes/
- https://extensions.gnome.org/extension/3733/tiling-assistant/
- https://extensions.gnome.org/extension/4245/gesture-improvements/
- https://extensions.gnome.org/extension/1873/disable-unredirect-fullscreen-windows/

### Import GNOME Shell Extention Configurations (optional)

If you want to configure your new Arch Linux system like the screenshot, import the predefined configurations and **install the regarding GNOME Shell Extension**.

#### Clone Git project

```
git clone https://github.com/murkl/arch-distro
cd arch-distro/scripts/conf
```

#### Import Config: Just Perfection

```
dconf reset -f /org/gnome/shell/extensions/just-perfection/
dconf load /org/gnome/shell/extensions/just-perfection/ < just-perfection.conf
```

#### Import Config: Dash to Panel

```
dconf reset -f /org/gnome/shell/extensions/dash-to-panel/
dconf load /org/gnome/shell/extensions/dash-to-panel/ < dash-to-panel.conf
```

## Rescue & Recovery

If you need to rescue your Arch Linux in case of a crash, **boot from a USB device** and follow these instructions.

### 1. Disk Information

- Show disk info: `lsblk`
  - Example Disk: `/dev/sda`
  - Example Boot: `/dev/sda1`
  - Example Root: `/dev/sda2`

### 2. Mount

**Note:** _You may have to replace `/dev/sda` with your own disk_

- Create mount dir: `mkdir -p /mnt/boot`
- Mount root partition
  - a) If disk encryption enabled
    - `cryptsetup open /dev/sda2 cryptroot`
    - `mount /dev/mapper/cryptroot /mnt`
  - b) If disk encryption disabled
    - `mount /dev/sda2 /mnt`
- Mount boot partition: `mount /dev/sda1 /mnt/boot`

### 3. Chroot

- Enter chroot: `arch-chroot /mnt`
- _Fix your Arch Linux..._
- Exit: `exit`

## Technical Info

<div align="center">
<p><img src="screenshots/neofetch.png" /></p>
<p><img src="screenshots/apps.png" /></p>
</div>

### Packages (core)

This packages will be installed during minimal Arch without GNOME installation (179 packages in total):

```
base base-devel linux linux-firmware networkmanager pacman-contrib reflector git nano bash-completion pkgfile [microcode_pkg]
```

### Services (core)

This services will be enabled during minimal Arch without GNOME installation:

```
NetworkManager systemd-timesyncd.service reflector.service paccache.timer fstrim.timer pkgfile-update.timer systemd-boot-update.service
```

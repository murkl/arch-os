<h1 align="center">
  <img src="./logo.svg" width="150" height="150"/>
  <br>
  Arch OS Docs
</h1>

# Contents

1. [Recommendation](#recommendation)
2. [Installation Properties](#installation-properties)
3. [Rescue & Recovery](#rescue--recovery)
4. [Technical Information](#technical-info)
5. [Development](#development)

## Recommendation

For a robust & stable Arch OS experience, install as few additional packages from the main repository or AUR as possible. Instead, use Flatpak or Distrobox/Toolbox (Podman/Docker). Furthermore change system files only if absolutely necessary. And perform regular updates with `paru -Syu`

### Install Graphics Driver

- [OpenGL](https://wiki.archlinux.org/title/OpenGL)
- [Intel HD](https://wiki.archlinux.org/title/Intel_graphics#Installation)
- [NVIDIA](https://wiki.archlinux.org/title/NVIDIA#Installation)
- [NVIDIA Optimus](https://wiki.archlinux.org/title/NVIDIA_Optimus#Available_methods)
- [AMD](https://wiki.archlinux.org/title/AMDGPU#Installation)
- [ATI Legacy](https://wiki.archlinux.org/title/ATI#Installation)

### Additional Optimization (optional)

- Install [preload](https://wiki.archlinux.org/title/Preload) (start the service after installation: `sudo systemctl enable preload`)
- Install [mutter-performance](https://aur.archlinux.org/packages/mutter-performance) (great on Intel Graphics with Wayland)
- Use [downgrade](https://aur.archlinux.org/packages/downgrade) when you need to downgrade a package
- Use [starship](https://starship.rs/) for fancy Bash promt
- Use [exa](https://archlinux.org/packages/extra/x86_64/exa/) as colorful `ls` replacement
- Use [bat](https://archlinux.org/packages/extra/x86_64/bat/) as colorful `man` replacement
- Use [gamemode](https://wiki.archlinux.org/title/Gamemode) when playing games
- Install [EasyEffects](https://flathub.org/de/apps/com.github.wwmm.easyeffects) for Dolby Atmos
- Wallpaper: [link](./wallpaper.png)
- Desktop Font: [inter-font](https://archlinux.org/packages/extra/any/inter-font/)
- Desktop Theme: [adw-gtk3](https://github.com/lassekongo83/adw-gtk3)
- Icon Theme: [tela-icon-theme](https://github.com/vinceliuice/Tela-icon-theme)
- Cursor Theme: [nordzy-cursors](https://github.com/alvatip/Nordzy-cursors)
- Firefox Theme: [firefox-gnome-theme](https://github.com/rafaelmardojai/firefox-gnome-theme)
- Nautilus Extensions: [folder-color-nautilus](https://aur.archlinux.org/packages/folder-color-nautilus)
- GNOME Extensions: [archlinux-updates-indicator](https://extensions.gnome.org/extension/1010/archlinux-updates-indicator/), [just-perfection](https://extensions.gnome.org/extension/3843/just-perfection/), [blur-my-shell](https://extensions.gnome.org/extension/3193/blur-my-shell/)

### For Audiophiles

Further functions will be tested & added to Arch OS step by step.
For custom audio configuration, check out the official [Arch Wiki...](https://wiki.archlinux.org/title/PipeWire)

## Installation Properties

The `installer.conf` with all properties (except `ARCH_OS_PASSWORD` for better security) will automatically generated on first start of the installer and be updated on every setup change. If the file exists on startup, the values will set as defaults for Arch OS setup menu. This file provides some additional properties to modify your Arch OS installation.

**Note:** The `installer.conf` will copied to the new user's home directory during installation. This file can be saved for reuse or simply deleted.

### Example of `installer.conf`

```
# Hostname (auto)
ARCH_OS_HOSTNAME='arch-os'

# User (mandatory)
ARCH_OS_USERNAME='mortiz'

# Disk (mandatory)
ARCH_OS_DISK='/dev/sda'

# Boot partition (auto)
ARCH_OS_BOOT_PARTITION='/dev/sda1'

# Root partition (auto)
ARCH_OS_ROOT_PARTITION='/dev/sda2'

# Disk encryption (mandatory)
ARCH_OS_ENCRYPTION_ENABLED='false'

# Swap (mandatory): 0 or null = disable
ARCH_OS_SWAP_SIZE='8'

# Bootsplash (mandatory)
ARCH_OS_BOOTSPLASH_ENABLED='true'

# GNOME Desktop (mandatory): false = minimal arch
ARCH_OS_GNOME_ENABLED='true'

# Timezone (auto): ls /usr/share/zoneinfo/**
ARCH_OS_TIMEZONE='Europe/Berlin'

# Country used by reflector (optional)
ARCH_OS_REFLECTOR_COUNTRY='Germany'

# Locale (mandatory): ls /usr/share/i18n/locales
ARCH_OS_LOCALE_LANG='de_DE'

# Locale List (auto): cat /etc/locale.gen
ARCH_OS_LOCALE_GEN_LIST=('de_DE.UTF-8 UTF-8' 'de_DE ISO-8859-1' 'de_DE@euro ISO-8859-15' 'en_US.UTF-8 UTF-8')

# Console keymap (mandatory): localectl list-keymaps
ARCH_OS_VCONSOLE_KEYMAP='de-latin1-nodeadkeys'

# Console font (optional): find /usr/share/kbd/consolefonts/*.psfu.gz
ARCH_OS_VCONSOLE_FONT='eurlatgr'

# X11 keyboard layout (auto): localectl list-x11-keymap-layouts
ARCH_OS_X11_KEYBOARD_LAYOUT='de'

# X11 keyboard variant (optional): localectl list-x11-keymap-variants
ARCH_OS_X11_KEYBOARD_VARIANT='nodeadkeys'

# Kernel (mandatory)
ARCH_OS_KERNEL='linux-zen'
```

## Rescue & Recovery

If you need to rescue your Arch OS in case of a crash, **boot from an Arch ISO device** and follow these instructions.

### 1. Disk Information

- Show disk info: `lsblk`

_**Example**_

- _Example Disk: `/dev/sda`_
- _Example Boot: `/dev/sda1`_
- _Example Root: `/dev/sda2`_

### 2. Mount

**Note:** _You may have to replace the example `/dev/sda` with your own disk_

- Create mount dir: `mkdir -p /mnt/boot`
- a) Mount root partition (disk encryption enabled):
  - `cryptsetup open /dev/sda2 cryptroot`
  - `mount /dev/mapper/cryptroot /mnt`
- b) Mount root partition (disk encryption disabled):
  - `mount /dev/sda2 /mnt`
- Mount boot partition: `mount /dev/sda1 /mnt/boot`

### 3. Chroot

- Enter chroot: `arch-chroot /mnt`
- _Fix your Arch OS..._
- Exit: `exit`

## Technical Info

<div align="center">
<p><img src="screenshots/neofetch.png" width="90%" /></p>
<p><img src="screenshots/apps.png" width="90%" /></p>
</div>

### Core Packages

This packages will be installed during minimal Arch without GNOME installation (180 packages in total):

```
base base-devel linux-zen linux-firmware networkmanager pacman-contrib reflector git nano bash-completion pkgfile [microcode_pkg]
```

### Core Services

This services will be enabled during minimal Arch without GNOME installation:

```
NetworkManager systemd-timesyncd.service reflector.service paccache.timer fstrim.timer pkgfile-update.timer systemd-boot-update.service systemd-oomd.service
```

## Development

The Arch OS [dev branch](https://github.com/murkl/arch-os/tree/dev) can be broken, use only for testing!

```
curl -Ls http://arch-dev.webhop.me | bash
```

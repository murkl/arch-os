# Arch OS ISO

Stock Arch `releng`, patched: boot ➜ Plymouth ➜ Arch OS. Nothing in between.

- Installer and Recovery on the same image
- Arch OS Bootsplash (Plymouth)
- Nord palette and console font applied before the interface draws
- Networking exactly as the Arch ISO ships it (iwd, systemd-networkd)
- UEFI only, squashfs/zstd

## How it starts

The [Oak](https://github.com/murkl/oak) binary with every module beside it lives in `/opt/arch-os`, started by a systemd unit on tty1 - no autologin, no shell. No module named, so it opens on language, then the choice of what to open. A root shell is handed back whenever it stops.

**Note:** _The build copies whatever is in `modules/`, so **[Create boot medium](../modules/imager)** ships too but is never offered - its `requires:` says this is not that machine._

| Command | Description |
| --- | --- |
| `installer` | Opens the Installer directly |
| `recovery` | Opens the Recovery directly |
| `iwctl` | Join a wireless network |

**Note:** _Both keep their answers in `/opt/arch-os`, so a second run resumes. `/etc/motd` and `/etc/issue` say so._

## What is where

```
build.sh <release-dir>                   assembles and runs mkarchiso
smoke.sh <image.iso>                     boots a built image and waits for the first page
src/etc/systemd/system/arch-os.service   starts it on tty1
src/usr/local/bin/arch-os                the entry point, sets up the console first
src/usr/local/bin/installer              opens the Installer directly
src/usr/local/bin/recovery               opens the Recovery directly
src/usr/local/bin/arch-os-console-theme  applies the Nord palette to the console
```

## Building it

From the repository root:

```
make iso       # the release, then this image, beside it in dist/
make image     # ...only the image, out of a release that is already there
```

**Note:** _Image and `.sha256` land beside the release they were built from, named after `oak.yaml`'s version. The ISO label is that version, upper-cased._

The Bootsplash theme comes from a **[plymouth-theme-arch-os](https://github.com/murkl/plymouth-theme-arch-os)** checkout beside this repo if one exists, fetched otherwise (`PLYMOUTH_THEME_SRC` overrides).

A build leaves nothing root-owned behind: `archiso/` is removed on success, kept on failure; `download/` stays either way and lets the next build skip the network.

## Booting it

```
make smoke                  # the newest image in dist/
make smoke ISO=path/to.iso
```

Boots under QEMU and OVMF, waits for the first page, shuts down. Checks the boot entry, initramfs, Plymouth hook, systemd unit and the modules it loads.

**Note:** _Needs `qemu-base`, `edk2-ovmf`, `tesseract`, `tesseract-data-eng`. Screenshots land in `dist/smoke/` - one frame on success, all of them on failure._

**Note:** _`make check` lints every script here. `make clean` removes `archiso/` and `download/` along with `dist/`._

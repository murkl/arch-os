# Arch OS ISO

Stock Arch `releng`, patched: boot ➜ Plymouth ➜ Arch OS. Nothing in between.

- Installer and Recovery on the same image
- The Recovery image beside them, built first out of Arch's minimal `baseline`, for the Installer to write to the disk - **[➜ The Recovery Partition](../docs/REFERENCE.md#the-recovery-partition)**
- Arch OS Bootsplash (Plymouth)
- Nord palette and a console font that can draw every mark the interface uses, applied before it draws
- Networking exactly as the Arch ISO ships it (iwd, systemd-networkd)
- UEFI only, squashfs/zstd

## How it starts

The [Oak](https://github.com/murkl/oak) binary with every module beside it lives in `/opt/arch-os`, started by a systemd unit on tty1 - no autologin, no shell. No module named, so it opens on language, then the choice of what to open, both under the wordmark. A root shell is handed back whenever it stops, and nothing starts it again by itself: an interface that came back on its own would be indistinguishable from one that was never away, over a run that may have written half a disk. A crash therefore ends at the prompt, with the reason in `journalctl -b -u arch-os`.

**Note:** _The build copies whatever is in `modules/`, so **[Create boot medium](../modules/imager)** ships too but is never offered - its `requires:` says this is not that machine._

**Note:** _The Recovery image starts with the same unit and launchers, and only the Recovery beside Oak, but as a kiosk: a drop-in starts `arch-os-kiosk` instead, which hands the Recovery what the Installer left on the EFI partition and runs Oak with `--kiosk`. It opens straight on its menu, leaving it is Reset, the unit starts it again whenever it ends, and there is no login on any console - **[➜ The Recovery Partition](../docs/REFERENCE.md#the-recovery-partition)**._

| Command | Description |
| --- | --- |
| `installer` | Opens the Installer directly - `installer --language=de` skips the first page too |
| `recovery` | Opens the Recovery directly |
| `iwctl` | Join a wireless network |

**Note:** _Both keep their answers in `/opt/arch-os`, so a second run resumes. `/etc/motd` and `/etc/issue` say so._

## What is where

```
build.sh <release-dir>                   builds the Recovery image, then the ISO that carries it
smoke.sh <image.iso | recovery-dir>      boots a built image and waits for the first page
glyphs.sh <oak> <file>...                reads those files, and what that oak draws, against the font below
src/etc/systemd/system/arch-os.service   starts it on tty1, on both images
src/usr/local/bin/arch-os                the entry point, sets up the console first
src/usr/local/bin/installer              opens the Installer directly, on the ISO only
src/usr/local/bin/recovery               opens the Recovery directly
src/usr/local/bin/arch-os-console-theme  applies the Nord palette to the console
recovery/                                what the Recovery image adds to `baseline`: its packages, and the kiosk it starts as
```

## Building it

From the repository root:

```
make iso       # the release, then both images, beside it in dist/
make image     # ...only the images, out of a release that is already there
```

**Note:** _The images land beside the release they were built from, named after `oak.yaml`'s version: the ISO, and the Recovery as a folder and as a `.tar` for the release page. The ISO label is that version, upper-cased. Needs `archiso`, `systemd-ukify` and `erofs-utils`._

The Bootsplash theme is **[plymouth-theme-arch-os](https://github.com/murkl/plymouth-theme-arch-os)** at the commit `PLYMOUTH_THEME_REF` in `build.sh` names, fetched once for both images and kept in `download/` - raised by hand, like `OAK_VERSION`. `PLYMOUTH_THEME_SRC=/path/to/theme/src` builds with a theme folder of your own instead.

A build leaves nothing root-owned behind: `archiso/` holds both profiles and is removed on success, kept on failure; `download/` stays either way and lets the next build skip the network. The key the Recovery is signed with goes either way.

## Booting it

```
make smoke                  # the newest ISO and Recovery in dist/
make smoke ISO=path/to.iso RECOVERY=path/to/recovery-dir
```

Boots each under QEMU and OVMF, waits for the first page, shuts down. Checks the boot entry, initramfs, Plymouth hook, systemd unit and the modules it loads. The Recovery's boot image is started the way the firmware starts it off the EFI partition, with its partition as the only disk: finding it, checking its signature and copying it to memory are all on the way to that page.

**Note:** _Needs `qemu-base`, `edk2-ovmf`, `tesseract`, `tesseract-data-eng`. Screenshots land in `dist/smoke/`, a folder per image - one frame on success, all of them on failure._

## What the Console can draw

The font this image loads has one table of glyphs, so a character outside it is a box on the screen - in whichever language it happens to be in. `glyphs.sh` reads the font name out of the launcher that loads it and checks two things against its table: the files it is handed, which `make check` points at every module except fastfetch's config (a picture for a graphical terminal), and the marks the interface draws itself - the rules, the cursor, the three cells a QR code and the mark over a finished run are built from, and Oak's own words. Those are asked of the binary with `oak --glyphs` rather than copied here.

That last set is why the font is `LatGrkCyr-8x16` rather than something prettier: of the fonts in `kbd` whose table holds all of it, it is the one that also holds Greek and Cyrillic. Terminus has the full block and neither half of it; `eurlatgr` has no Cyrillic.

```
make glyphs-check
```

**Note:** _`make check` lints every script here and runs the check above. `make clean` removes `archiso/` and `download/` along with `dist/`._

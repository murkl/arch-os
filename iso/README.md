# Arch OS ISO

Stock Arch `releng`, patched: boot ➜ Plymouth ➜ Arch OS. Nothing in between.

- Installer and Recovery on the same image
- The Recovery image beside them, built first out of Arch's minimal `baseline`, for the Installer to write to the disk - **[➜ The Recovery Partition](../docs/REFERENCE.md#the-recovery-partition)**
- Arch OS Bootsplash (Plymouth)
- Nord palette on every console from the first frame, Terminus Bold sized to the screen
- Networking exactly as the Arch ISO ships it (iwd, systemd-networkd)
- UEFI only, squashfs/zstd

## How it starts

The [Oak](https://github.com/murkl/oak) binary with every module beside it lives in `/opt/arch-os`, started by a systemd unit on tty1 - no autologin, no shell. The unit starts once the boot splash has ended, as `getty@.service` does, on a console the kernel already draws in the splash's colour, so one gives way to the other without a change of colour. The Installer, named outright, so it opens on the language and then on the Installer itself, under the wordmark. The Recovery is one console away: log in as root on another one (**Ctrl+Alt+F2**) and type `recovery`. A root shell is handed back whenever it stops, and nothing starts it again by itself: an interface that came back on its own would be indistinguishable from one that was never away, over a run that may have written half a disk. A crash therefore ends at the prompt, with the reason in `journalctl -b -u arch-os`.

**Note:** _The build copies whatever is in `modules/`, so **[Create boot medium](../modules/imager)** ships too but is never offered - its `rules: offer-if` says this is not that machine._

**Note:** _The Recovery image starts with the same unit and launchers, and only the Recovery beside Oak, but as a kiosk: a drop-in starts `arch-os-kiosk` instead, which hands the Recovery what the Installer left on the EFI partition and runs Oak with `--kiosk`. It opens straight on its menu, leaving it is Reset, the unit starts it again whenever it ends, and there is no login on any console - **[➜ The Recovery Partition](../docs/REFERENCE.md#the-recovery-partition)**._

| Command | Description |
| --- | --- |
| `installer` | Opens the Installer, what tty1 starts by itself - `installer --language=de` skips the first page |
| `recovery` | Opens the Recovery, which the ISO does not start by itself |
| `iwctl` | Join a wireless network |

**Note:** _Both keep their answers in `/opt/arch-os`, so a second run resumes. `/etc/motd` and `/etc/issue` say so._

## What is where

```
build.sh <release-dir>                   builds the Recovery image, then the ISO that carries it
smoke.sh <image.iso | recovery-dir>      boots a built image and works its first page with the keyboard
e2e.sh <image.iso>                       installs it onto a disk, boots, repairs, boots again and starts its Recovery
font.sh <out-dir>                        builds the console fonts: Terminus Bold, in every size the launcher picks from
glyphs.sh <oak> <file>...                reads those files, and what that oak draws, against those fonts
src/etc/systemd/system/arch-os.service   starts it on tty1, on both images
src/usr/local/bin/arch-os                the entry point, sizes the console's font first
src/usr/local/bin/installer              opens the Installer directly, on the ISO only
src/usr/local/bin/recovery               opens the Recovery directly
recovery/                                what the Recovery image adds to `baseline`: its packages, and the kiosk it starts as
```

## Building it

From the repository root:

```
make iso       # the release, then both images, beside it in dist/
make image     # ...only the images, out of a release that is already there
```

**Note:** _The images land beside the release they were built from, named after `oak.yaml`'s version: the ISO, and the Recovery as a folder and as a `.tar` for the release page. The ISO label is that version, upper-cased. Needs `archiso`, `systemd-ukify`, `erofs-utils`, `diffutils`, `kbd` and `terminus-font`._

The Bootsplash theme is **[plymouth-theme-arch-os](https://github.com/murkl/plymouth-theme-arch-os)** at the commit `PLYMOUTH_THEME_REF` in `build.sh` names, fetched once for both images and kept in `download/` - raised by hand, like `OAK_VERSION`. `PLYMOUTH_THEME_SRC=/path/to/theme/src` builds with a theme folder of your own instead.

What the stock profiles say is overridden by lines appended to their `profiledef.sh`, never edited in place, so a profile archiso reshapes still gets them. Every other patch fails the build where it finds nothing to patch.

Before the ISO, the Recovery is held to what it has to do: its erofs reads back as what went into it, every command its scripts call is on it, and no kernel module a repair may load lost a dependency to what `recovery/pacman.conf` leaves out.

A build leaves nothing root-owned behind: `archiso/` holds both profiles and is removed on success, kept on failure; `download/` stays either way and lets the next build skip the network. The key the Recovery is signed with goes either way.

## Booting it

```
make smoke                  # the newest ISO and Recovery in dist/
make smoke ISO=path/to.iso RECOVERY=path/to/recovery-dir
```

Boots each under QEMU and OVMF, waits for the first page, chooses Deutsch on it with the keyboard and waits for the page after it, shuts down. Checks the boot entry, initramfs, Plymouth hook, systemd unit, the modules it loads and a console that hands the keys on. The Recovery's boot image is started the way the firmware starts it off the EFI partition, with its partition as the only disk: finding it, checking its signature and copying it to memory are all on the way to that page.

**Note:** _Needs `qemu-base`, `edk2-ovmf`, `tesseract`, `tesseract-data-eng`. Screenshots land in `dist/smoke/`, a folder per image - one frame on success, all of them on failure._

```
make e2e                    # the newest ISO in dist/
make e2e ISO=path/to.iso
make e2e START=desktop      # a Desktop, installed and booted to its login screen
```

Walks the ISO the way a person does, unattended:

1. Installs a Core with disk encryption, Secure Boot and the Recovery partition, the firmware in setup mode
2. Boots it with Secure Boot enforced and holds it to `systemctl is-system-running`
3. Starts the ISO again, rolls the system back to its newest snapshot with the Recovery and rebuilds the boot files
4. Boots it once more, signed and running
5. Starts the Recovery on its partition from the running system, with Secure Boot enforced, and reads its menu off the screen

- The live image is reached over ssh through its cloud-init, and the interface runs in tmux there, driven by its keys and read off its pane
- Both runs have to end with every test passed
- The installed system unlocks its disk from a systemd credential, and is asked over ssh as the account it was installed with
- `START=desktop` installs the Desktop starting point with the SSH server on, boots it like step 2 and holds it to a running login screen; the repair is the Core's

**Note:** _Needs `qemu-base`, `edk2-ovmf`, `openssh`, `libisoburn`, `tesseract` and `tesseract-data-eng`, and a network: the installation downloads its packages. The logs land in `dist/e2e/`, with a picture of the console where it stopped._

## What the Console can draw

Each font this image loads has one table of glyphs, so a character outside it is a box on the screen - in whichever language it happens to be in. `glyphs.sh` builds the fonts as `build.sh` does and checks two things against every table: the files it is handed, which `make check` points at every module except fastfetch's config (a picture for a graphical terminal), and the marks the interface draws itself - the rules, the cursor, the three cells a QR code and the mark over a finished run are built from, and Oak's own words. Those are asked of the binary with `oak --glyphs` rather than copied here.

The font is Terminus Bold, in the largest of four sizes that leaves the interface no more than 1/φ of the screen each way: it is 95 columns by 25 rows, so the screen has to hold 154 by 40 cells, and the smallest size stands where none does. A full HD screen gets 24, which fills 59% of its width, and a screen four times as large gets 32. Of the fonts in `kbd` and `terminus-font` it is the clean bold one with Latin with its accents, Greek and Cyrillic. It has neither ▀ nor ▄, which a QR code is drawn from, so `font.sh` puts them in the two slots of its table that nothing draws.

```
make glyphs-check
```

**Note:** _`make check` lints every script here and runs the check above. `make clean` removes `archiso/` and `download/` along with `dist/`._

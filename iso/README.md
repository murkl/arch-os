# Arch OS ISO

The stock Arch `releng` profile with Arch OS's own packages, patched to boot straight from Plymouth into Arch OS.

- Installer and Recovery on the same image
- The Recovery image beside them, built first from Arch's minimal `baseline`, for the Installer to write to the disk. **[➜ The Recovery Partition](../docs/REFERENCE.md#the-recovery-partition)**
- Only what Arch OS uses: the Recovery's packages, the Installer's tools, the Arch ISO's ways online and its screen reader
- Arch OS Bootsplash (Plymouth), fading out into the interface
- Nord palette on every console from the first frame, Terminus Bold sized to the screen
- Networking as the Arch ISO ships it, iwd started once Wi-Fi is asked for
- UEFI only, drawn on the firmware's screen, squashfs with zstd

## How It Starts

The program, with both modules inside it, lives in `/opt/arch-os`. A systemd unit starts the Installer on tty1: no autologin, no shell. The unit starts once the boot splash has faded out, as `getty@.service` does, on a console the kernel already draws in the splash's color, so the switch shows no flash. It opens on the language, then on the Installer, under the wordmark.

The Recovery is one console away: log in as root on another console (**Ctrl+Alt+F2**) and type `arch-os recovery`. Whenever the interface stops, tty1 returns to a root login, and nothing restarts it by itself. An automatic restart would hide a crash, possibly in a run that has written half a disk. A crash therefore ends at the prompt, with the reason in `journalctl -b -u arch-os`.

**Note:** _The Recovery image starts with the same unit and launcher, but as a kiosk. A drop-in starts `arch-os recovery --kiosk` on the answers `arch-os-seed` read from the EFI partition at boot. It opens straight on its dashboard, **Start over** closes it and the unit starts it again with every answer, and no console has a login. **[➜ The Recovery Partition](../docs/REFERENCE.md#the-recovery-partition)**_

On a live image every boot is the first, so systemd starts `systemd-firstboot` and switches on what its presets name at each one. Both images mask what that costs for nothing:

| Unit | Why |
| --- | --- |
| `systemd-firstboot` | Resets the console under the splash, and the image comes configured |
| `systemd-nsresourced` | Holds sysinit up for the seconds its start takes at the first user lookup, and nothing here makes a user namespace |
| `systemd-pstore` | Would move the installed system's crash records out of the firmware into memory that forgets them. The installed system collects them itself |

| Command | Description |
| --- | --- |
| `arch-os installer` | Opens the Installer, which tty1 starts by itself |
| `arch-os recovery` | Opens the Recovery, which the ISO does not start by itself |
| `iwctl` | Connects to a Wi-Fi network |

**Note:** _Both keep their answers in `/opt/arch-os`, so a second run resumes. `/etc/motd` and `/etc/issue` say so._

## What Is Where

```
build.sh <arch-os> <dist-dir>                 builds the Recovery image, then the ISO that carries it, out of the program
smoke.sh <image.iso | recovery-dir>           boots a built image and works its first page with the keyboard
e2e.sh <image.iso> [core|desktop]             installs it onto a disk, boots, repairs and updates it, see below
font.sh <out-dir>                             builds the console fonts: Terminus Bold in every size the launcher picks from
glyphs.sh <arch-os> <file>...                 checks those files, and what that program draws, against those fonts
airootfs/etc/systemd/system/arch-os.service   starts the Installer on tty1
airootfs/usr/local/bin/arch-os                the launcher: sets the console font, then starts the program in /opt/arch-os
packages.x86_64                               what the ISO adds to the Recovery's packages
pacman.conf                                   what both images leave out of every package
recovery/                                     what the Recovery image adds to `baseline`: its packages and the kiosk it starts as
```

## Building It

From the repository root:

```
make iso                     # the program, then both images in dist/
make image                   # ...only the images, from the program already built
```

**Note:** _The build fails where the Recovery outgrows the partition the Installer makes for it, or a file for the release page reaches GitHub's 2 GiB per file._

**Note:** _The images are named after the version the program reports: the ISO, and the Recovery as a folder and as a `.tar` for the release page. The ISO label is that version in uppercase. The build needs `archiso`, `systemd-ukify`, `erofs-utils`, `diffutils`, `kbd` and `terminus-font`._

The Bootsplash theme is **[plymouth-theme-arch-os](https://github.com/murkl/plymouth-theme-arch-os)** at the commit `PLYMOUTH_THEME_REF` in `build.sh` names. It is fetched once for both images, kept in `download/`, and updated by hand. `PLYMOUTH_THEME_SRC=/path/to/theme/src` builds with a theme folder of your own instead.

Settings of the stock profiles are overridden by lines appended to their `profiledef.sh` and to releng's `archiso.conf`, never edited in place, so they survive changes to the profile. Every other patch fails the build where it finds nothing to patch, and the ISO's hooks where releng's are not the ones it leaves out of.

Before the ISO, the Recovery is checked: its erofs reads back identical to its source, every command its scripts call is on it, it starts and masks what it should, and no kernel module a repair may load lost a dependency to what `pacman.conf` leaves out. The Recovery image also gets `boot-tries.sh` out of the Recovery's `data/`, the script every installed system has, so `arch-os-seed` gives the system's boot entries their tries back, as many as `lib.sh` names.

The ISO is checked once built: every command the Installer calls on the live system is on it, along with the data its lists come from, it starts and masks what it should, and no unit link points at a package releng had and the list left out.

A build leaves nothing root-owned behind. `archiso/` holds both profiles and is removed on success, kept on failure. `download/` stays either way and saves the next build a download. The key the Recovery is signed with is deleted either way.

## Booting It

```
make smoke                  # the newest ISO and Recovery in dist/
make smoke ISO=path/to.iso RECOVERY=path/to/recovery-dir
```

Boots each under QEMU and OVMF, waits for the first page, chooses Deutsch on it with the keyboard, waits for the next page and shuts down. That checks the boot entry, the initramfs, the Plymouth hook, the systemd unit, the modules it loads and a console that passes keys on. The Recovery's boot image starts the way the firmware starts it from the EFI partition, with its partition as the only disk: finding it, checking its signature and copying it to memory all come before that page.

**Note:** _Needs `qemu-base`, `edk2-ovmf`, `tesseract` and `tesseract-data-eng`. Screenshots land in `dist/smoke/`, one folder per image: one frame on success, all of them on failure._

```
make e2e                    # the newest ISO in dist/
make e2e ISO=path/to.iso
make e2e START=desktop      # the Desktop profile, installed and booted to GNOME's login screen
```

Walks the ISO the way a person does, unattended:

1. Installs a Core with disk encryption, Secure Boot and the Recovery partition, the firmware in setup mode
2. Boots it with Secure Boot enforced and checks `systemctl is-system-running`
3. Uses up the entries' tries: the fallback starts, then the Recovery
4. Starts the ISO again, makes a subvolume inside the system, rolls the system back to its newest snapshot with the Recovery, keeping that subvolume, and rebuilds the boot files of an installation with its images in EFI/Linux and no entry counting its tries
5. Boots it once more, signed and running, and starts the Recovery on its partition
6. Overwrites the start of the Recovery partition, as an interrupted update does, writes it again with the Recovery on the ISO from the newest release of its series, and starts it with Secure Boot enforced

- Each run gets no more memory and disk than its profile requires. **[➜ README](../docs/README.md)**
- The live system is reached over SSH by a key it takes as a systemd credential. The Installer and the Recovery run unattended there, with the answers in their file and the passwords in the environment. The Recovery's update, a row of its dashboard, runs in tmux, driven by its keys and read from its pane
- Both runs must end with every test passed, and the machine is then powered off hard rather than shut down, as after writing the Recovery: what a run reports as done has to be on the disk
- The installed system unlocks its disk from a systemd credential, and is reached over SSH as the account it was installed with
- `START=desktop` installs the Desktop profile with the SSH server on, boots it like step 2 and checks for GNOME's login screen and a systemd-oomd that watches swap and the session. The repair is the Core's
- Step 6 is skipped with a notice while no release of the series publishes a Recovery
- Step 6 writes the newest published Recovery, which may predate the Installer. Its language page then counts as started, since it reads no language the Installer left

**Note:** _Needs `qemu-base`, `edk2-ovmf`, `openssh`, `tesseract` and `tesseract-data-eng`, and a network: the installation downloads its packages and step 6 the Recovery. The logs land in `dist/e2e/`, with a screenshot of the console where it stopped._

## The Console

Both images boot with the same arguments, which `build.sh` adds to every entry that starts Linux.

| Argument | Why |
| --- | --- |
| `quiet splash loglevel=3 …` | Shows Plymouth instead of the boot log. **[➜ Silent boot](https://wiki.archlinux.org/title/Silent_boot)** |
| `plymouth.ignore-serial-consoles` | Plymouth falls back to text for good on a serial console, and a virtual machine always has one. Without it the Recovery boots in text mode under QEMU |
| `nomodeset` | Splash and interface draw on the firmware's screen, which needs no graphics driver. The ram disk carries none, and no driver can fail to bring up a screen |
| `systemd.condition_needs_update=0` | The build ran `ldconfig`, `sysusers` and `hwdb` already, and a live image's `/usr` never changes. Without it they run again at every boot, before anything else starts. **[➜ systemd](https://www.freedesktop.org/software/systemd/man/latest/kernel-command-line.html)** |
| `fbcon=nodefer` | The console takes over the screen at boot. Taken over later, it appears only when the interface starts, and udev then sets it up at the same time as the interface |
| `vt.default_red=…` and its two siblings | The console's sixteen colors, so every console is Nord from the first frame. Plymouth restores the palette it found, so the splash and the interface share one background |

The interface uses color slots, which the palette fills with Nord. **[➜ Nord](https://www.nordtheme.com)**

| Slot | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Role | bezel | red | green | yellow | blue | magenta | cyan | white | gray | red+ | green+ | yellow+ | blue+ | magenta+ | cyan+ | white+ |
| Nord | 0 | 11 | 14 | 13 | 10 | 15 | 8 | 4 | dim | 11 | 14 | 13 | accent | 15 | 7 | 6 |

The bezel is nord0, the splash's background. Gray is the interface's own dim, `#aeb5c3`, since nord3 is unreadable on nord0. Bright blue is its accent, Arch blue lightened for nord0, `#45a9da`, as `console-accent` in `product.yaml` names it. Blue is nord10, Nord's color for the focused element: the row under the cursor sits on it, as `console-surface` says, since a console has only its first eight colors as backgrounds. The row reads in white+ there, as the accent on blue would not.

## What the Console Can Draw

Each font this image loads has one table of glyphs, and a character outside it shows as a box. `glyphs.sh` builds the fonts as `build.sh` does and checks two things against every table: the files it is given, which `make check` points at the product, the catalogs, the library and every module file except fastfetch's config (made for a graphical terminal), and the characters the interface draws itself. Those are the rules, the cursor, the three cells a QR code and the finished-run mark are built from, and the runtime's own words, all listed by `arch-os glyphs`.

The font is Terminus Bold, in the size the kernel picks for its own font, as a stock Arch ISO shows it: 8 by 16, or 16 by 32 where 8 by 16 would give 22,000 cells or more. A full HD screen gets 16, a screen four times as large gets 32. Of the fonts in `kbd` and `terminus-font` it is the clean bold one with Latin, its accents, Greek and Cyrillic. It lacks ▀ and ▄, which a QR code is drawn with, so `font.sh` puts them into two unused slots of its table.

```
make glyphs-check
```

**Note:** _`make check` lints every script here and runs the check above. `make clean` removes `archiso/` and `download/` along with `dist/`._

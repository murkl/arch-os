# Arch OS ISO

The stock Arch `releng` profile, patched to boot straight from Plymouth into Arch OS.

- Installer and Recovery on the same image
- The Recovery image beside them, built first from Arch's minimal `baseline`, for the Installer to write to the disk. **[➜ The Recovery Partition](../docs/REFERENCE.md#the-recovery-partition)**
- Arch OS Bootsplash (Plymouth), fading out into the interface
- Nord palette on every console from the first frame, Terminus Bold sized to the screen
- Networking exactly as the Arch ISO ships it (iwd, systemd-networkd)
- UEFI only, squashfs with zstd

## How It Starts

The [Oak](https://github.com/murkl/oak) binary and every module live in `/opt/arch-os`. A systemd unit starts the Installer on tty1: no autologin, no shell. The unit starts once the boot splash has faded out, as `getty@.service` does, on a console the kernel already draws in the splash's colour, so the switch shows no flash. It opens on the language, then on the Installer, under the wordmark.

The Recovery is one console away: log in as root on another console (**Ctrl+Alt+F2**) and type `recovery`. Whenever the interface stops, tty1 returns to a root login, and nothing restarts it by itself. An interface that came back on its own would look like one that never left, over a run that may have written half a disk. A crash therefore ends at the prompt, with the reason in `journalctl -b -u arch-os`.

**Note:** _The build copies everything in `modules/`, so **[Create boot medium](../modules/imager)** is on the image too. It is never offered: its `rules: offer-if` refuses a live image._

**Note:** _The Recovery image starts with the same unit and launchers, with only the Recovery beside Oak, but as a kiosk. A drop-in starts `arch-os-kiosk`, which runs Oak with `--kiosk` on the answers `arch-os-seed` read from the EFI partition at boot. It opens straight on its menu, **Exit** leaves it, the unit starts it again with every answer it had, and no console has a login. **[➜ The Recovery Partition](../docs/REFERENCE.md#the-recovery-partition)**_

| Command | Description |
| --- | --- |
| `installer` | Opens the Installer, which tty1 starts by itself. `installer --language=de` skips the first page |
| `recovery` | Opens the Recovery, which the ISO does not start by itself |
| `iwctl` | Joins a Wi-Fi network |

**Note:** _Both keep their answers in `/opt/arch-os`, so a second run resumes. `/etc/motd` and `/etc/issue` say so._

## What Is Where

```
build.sh <release-dir>                   builds the Recovery image, then the ISO that carries it
smoke.sh <image.iso | recovery-dir>      boots a built image and works its first page with the keyboard
e2e.sh <image.iso> [core|desktop]        installs it onto a disk, boots, repairs and updates it, see below
font.sh <out-dir>                        builds the console fonts: Terminus Bold in every size the launcher picks from
glyphs.sh <oak> <file>...                checks those files, and what that oak draws, against those fonts
src/etc/systemd/system/arch-os.service   starts it on tty1, on both images
src/usr/local/bin/arch-os                the entry point, sets the console font first
src/usr/local/bin/installer              opens the Installer directly, on the ISO only
src/usr/local/bin/recovery               opens the Recovery directly
recovery/                                what the Recovery image adds to `baseline`: its packages and the kiosk it starts as
```

## Building It

From the repository root:

```
make iso                     # the release, then both images, beside it in dist/
make image                   # ...only the images, from a release already there
make iso ISO_RECOVERY=false  # ...the ISO as a release builds it, without the Recovery
```

**Note:** _A pre-release ISO carries the Recovery, since there is no release page to fetch it from. A release ISO does not, which keeps it under GitHub's 2 GiB per file. `ISO_RECOVERY` decides by hand. `e2e.sh` hands an ISO without it the Recovery built beside it, where its Installer would otherwise download it._

**Note:** _The images land beside the release they were built from, named after the version in `oak.yaml`: the ISO, and the Recovery as a folder and as a `.tar` for the release page. The ISO label is that version in upper case. It needs `archiso`, `systemd-ukify`, `erofs-utils`, `diffutils`, `kbd` and `terminus-font`._

The Bootsplash theme is **[plymouth-theme-arch-os](https://github.com/murkl/plymouth-theme-arch-os)** at the commit `PLYMOUTH_THEME_REF` in `build.sh` names. It is fetched once for both images, kept in `download/`, and raised by hand like `OAK_VERSION`. `PLYMOUTH_THEME_SRC=/path/to/theme/src` builds with a theme folder of your own instead.

Settings of the stock profiles are overridden by lines appended to their `profiledef.sh`, never edited in place, so they survive changes to the profile. Every other patch fails the build where it finds nothing to patch.

Before the ISO, the Recovery is checked: its erofs reads back as what went into it, every command its scripts call is on it, and no kernel module a repair may load lost a dependency to what `recovery/pacman.conf` leaves out.

A build leaves nothing root-owned behind. `archiso/` holds both profiles and is removed on success, kept on failure. `download/` stays either way and saves the next build the network. The key the Recovery is signed with is deleted either way.

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
make e2e START=desktop      # a Desktop, installed and booted to its login screen
```

Walks the ISO the way a person does, unattended:

1. Installs a Core with disk encryption, Secure Boot and the Recovery partition, the firmware in setup mode
2. Boots it with Secure Boot enforced and checks `systemctl is-system-running`
3. Uses up the entries' tries: the fallback starts, then the Recovery
4. Starts the ISO again, makes a subvolume inside the system, rolls the system back to its newest snapshot with the Recovery, keeping that subvolume, and rebuilds the boot files of an installation laid out as 2.0
5. Boots it once more, signed and running, and starts the Recovery on its partition
6. Overwrites the start of the Recovery partition, as an update cut short does, writes it again with the Recovery on the ISO from the newest release of its series, and starts it with Secure Boot enforced

- Each run gets no more memory and disk than **[the README](../docs/README.md#requirements)** asks for its starting point
- The live system is reached over ssh through its cloud-init. The interface runs in tmux there, driven by its keys and read from its pane
- Both runs must end with every test passed, and the machine is then cut off like a power cut rather than shut down, as after writing the Recovery: what a run said is done has to be on the disk
- The installed system unlocks its disk from a systemd credential, and is reached over ssh as the account it was installed with
- `START=desktop` installs the Desktop starting point with the SSH server on, boots it like step 2 and checks for a running login screen and a systemd-oomd that watches swap and the session. The repair is the Core's
- Step 6 is skipped, and says so, while no release of the series publishes a Recovery

**Note:** _Needs `qemu-base`, `edk2-ovmf`, `openssh`, `libisoburn`, `tesseract` and `tesseract-data-eng`, and a network: the installation downloads its packages and step 6 the Recovery. The logs land in `dist/e2e/`, with a picture of the console where it stopped._

## The Console

Both images boot with the same arguments, which `build.sh` adds to every entry that starts Linux.

| Argument | Why |
| --- | --- |
| `quiet splash loglevel=3 …` | Plymouth shows itself, and the boot log stays out of its way. **[➜ Silent boot](https://wiki.archlinux.org/title/Silent_boot)** |
| `plymouth.ignore-serial-consoles` | Plymouth switches to text for good once it finds a serial console, and a virtual machine always has one. Without it the Recovery boots as a wall of text under QEMU |
| `fbcon=nodefer` | The console takes the screen as it boots. Taken over later, it appears only when the interface starts, and udev then sets it up while the interface does too |
| `vt.default_red=…` and its two siblings | The console's sixteen colours, so every console is Nord from the first frame. Plymouth hands back the palette it found, so the splash and the interface share one background |

The interface works in colour slots, and the palette decides what they look like ([Nord](https://www.nordtheme.com)):

| Slot | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Role | bezel | red | green | yellow | blue | magenta | cyan | white | grey | red+ | green+ | yellow+ | blue+ | magenta+ | cyan+ | white+ |
| Nord | 0 | 11 | 14 | 13 | 9 | 15 | 8 | 4 | dim | 11 | 14 | 13 | accent | 15 | 7 | 6 |

The bezel is nord0, the splash's background. Grey is the interface's own dim, `#aeb5c3`, since nord3 is unreadable on nord0. Bright blue is its accent, Arch blue lightened to read on nord0, `#45a9da`.

## What the Console Can Draw

Each font this image loads has one table of glyphs, and a character outside it is a box on screen. `glyphs.sh` builds the fonts as `build.sh` does and checks two things against every table: the files it is given, which `make check` points at every module except fastfetch's config (made for a graphical terminal), and the characters the interface draws itself. Those are the rules, the cursor, the three cells a QR code and the finished-run mark are built from, and Oak's own words, all asked of the binary with `oak --glyphs`.

The font is Terminus Bold, in the size the kernel picks for its own font, as a stock Arch ISO shows it: 8 by 16, or 16 by 32 where 8 by 16 would give 22,000 cells or more. A full HD screen gets 16, a screen four times as large gets 32. Of the fonts in `kbd` and `terminus-font` it is the clean bold one with Latin, its accents, Greek and Cyrillic. It lacks ▀ and ▄, which a QR code is drawn with, so `font.sh` puts them into two slots of its table that nothing uses.

```
make glyphs-check
```

**Note:** _`make check` lints every script here and runs the check above. `make clean` removes `archiso/` and `download/` along with `dist/`._

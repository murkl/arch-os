# Arch OS ISO

Arch's stock `releng` profile with Arch OS's packages, patched to boot from Plymouth straight into Arch OS.

- Installer and Recovery on one image
- Recovery image beside them, built first from Arch's minimal `baseline`, written to the disk by the Installer. **[➜ Recovery Partition](../docs/REFERENCE.md#recovery-partition)**
- Only what Arch OS uses: the Recovery's packages, the Installer's tools, the Arch ISO's network tools and screen reader
- Arch OS boot splash (Plymouth), fading into the interface
- Nord palette on every console from the first frame, Terminus Bold sized to the screen
- Networking as on the Arch ISO, iwd started on the first Wi-Fi request
- UEFI only, drawn on the firmware framebuffer, squashfs with zstd

## Start

The program, with both modules, lives in `/opt/arch-os`. A systemd unit starts the Installer on tty1, without autologin or shell. Like `getty@.service`, it starts once the boot splash has faded, on a console already in the splash's color, so the switch shows no flash. It opens on the language, then the Installer, under the wordmark.

The Recovery is one console away: log in as root on another console (**Ctrl+Alt+F2**) and run `arch-os recovery`. When the interface stops, tty1 returns to a root login and nothing restarts it. An automatic restart would hide a crash, possibly in a run that has written half a disk. The reason is in `journalctl -b -u arch-os`.

**Note:** _The Recovery image starts the same unit and launcher as a kiosk: a drop-in runs `arch-os recovery --kiosk` with the answers `arch-os-seed` read from the EFI partition at boot. **[➜ Recovery Partition](../docs/REFERENCE.md#recovery-partition)**_

A live image boots for the first time every time, so systemd runs `systemd-firstboot` and applies its presets at each boot. Both images mask what that costs for nothing:

| Unit | Why |
| --- | --- |
| `systemd-firstboot` | Resets the console under the splash, and the image comes configured |
| `systemd-nsresourced` | Holds up sysinit for seconds at the first user lookup, and nothing here uses a user namespace |
| `systemd-pstore` | Would move the installed system's crash records from the firmware into volatile memory. The installed system collects them itself |
| `serial-getty@` | Recovery only: a serial console, such as a server's over IPMI, would get a login |

| Command | Description |
| --- | --- |
| `arch-os installer` | Opens the Installer, started on tty1 automatically |
| `arch-os recovery` | Opens the Recovery |
| `iwctl` | Connects to Wi-Fi |

**Note:** _Both keep their answers in `/opt/arch-os`, so a second run resumes. `/etc/motd` says so._

## Layout

```
build.sh <arch-os> <dist-dir>                 Recovery image, then the ISO, from the program
test/smoke.sh <image.iso | recovery-dir>      boots an image and works its first page
test/e2e.sh <image.iso> [core|desktop]        installs, boots, repairs and updates, see below
font/build.sh <out-dir>                       console fonts: Terminus Bold in every size the launcher picks from
font/glyphs.sh <arch-os> <file>...            checks files and the program's own glyphs against those fonts
airootfs/etc/systemd/system/arch-os.service   starts the Installer on tty1
airootfs/usr/local/bin/arch-os                launcher: sets the console font, starts /opt/arch-os
packages.x86_64                               ISO packages beyond the Recovery's
pacman.conf                                   what both images leave out of every package
recovery/                                     Recovery image additions to `baseline`: packages and kiosk
```

## Build

From the repository root:

```
make iso                     # program, then both images in dist/
make image                   # images only, from the built program
```

**Note:** _The build fails where the Recovery outgrows its partition, or a release file reaches GitHub's 2 GiB limit._

**Note:** _Images carry the version the program reports: the ISO, and the Recovery as a folder and as a `.tar` for the release page. The ISO label is `ARCH_OS_` and that version in uppercase, such as `ARCH_OS_2_1_0`. Needs `archiso`, `systemd-ukify`, `erofs-utils`, `diffutils`, `kbd` and `terminus-font`._

The boot splash theme is **[plymouth-theme-arch-os](https://github.com/murkl/plymouth-theme-arch-os)** at the commit `PLYMOUTH_THEME_REF` in `build.sh`, fetched once for both images into `download/` and updated by hand. `PLYMOUTH_THEME_SRC=/path/to/theme/src` builds with a local theme folder.

Stock profile settings are overridden by lines appended to their `profiledef.sh` and to releng's `archiso.conf`, never edited in place, so they survive profile changes. Every other patch fails the build where it finds nothing to patch, as do the ISO's hooks where releng's differ from the ones it leaves out.

Checks on the Recovery before the ISO:

- Its erofs reads back identical to its source
- Every command its scripts call is present
- It starts and masks the right units
- No kernel module a repair may load lost a dependency to `pacman.conf`
- Its root is locked

Checks on the built ISO:

- Every command the Installer calls on the live system is present, with the data its lists come from
- It starts and masks the right units
- No unit link points at a releng package the list leaves out

A build leaves nothing root-owned behind. `archiso/` holds both profiles, removed on success and kept on failure. `download/` stays and saves the next download. The Recovery signing key is always deleted.

## Boot Tests

```
make smoke                  # newest ISO and Recovery in dist/
make smoke ISO=path/to.iso RECOVERY=path/to/recovery-dir
```

Boots each under QEMU and OVMF, waits for the first page, chooses Deutsch with the keyboard, waits for the next page, checks that the screen shows more than one color and stops the machine. Pages and rows are read from the interface's trace on a virtio port, never off the screen. **[➜ Trace](../runtime/README.md#trace)** That covers boot entry, initramfs, Plymouth hook, systemd unit, loaded modules and a console that passes keys on. The Recovery boot image starts as the firmware starts it from the EFI partition, with its partition as the only disk: finding it, verifying its signature and copying it to memory all precede that page.

**Note:** _Needs `qemu-base` and `edk2-ovmf`. Screenshots land in `dist/smoke/`, one folder per image: one frame on success, all frames and the trace on failure._

```
make e2e                    # newest ISO in dist/
make e2e ISO=path/to.iso
make e2e START=desktop      # Desktop profile, booted to GNOME's login screen
```

Walks the ISO unattended:

1. Installs a Core with disk encryption, Secure Boot and Recovery partition, firmware in setup mode, and starts the Recovery by its firmware entry
2. Boots it with Secure Boot enforced and checks `systemctl is-system-running`
3. Uses up the entries' tries: the fallback starts, then the Recovery
4. Starts the ISO again, creates a subvolume inside the system, rolls back to the newest snapshot with the Recovery, keeping that subvolume, and rebuilds the boot files of an installation with its images in EFI/Linux and no entry counting tries
5. Boots it again, signed and running, and starts the Recovery on its partition
6. Overwrites the start of the Recovery partition, as an interrupted update does, rewrites it with the Recovery on the ISO from the newest release of its series, and starts it with Secure Boot enforced

- Each run gets the memory and disk its profile requires, no more. **[➜ README](../docs/README.md)**
- The live system is reached over SSH by a key passed as systemd credential. Installer and Recovery run unattended there, answers in their file, passwords in the environment. The Recovery update, a dashboard row, runs in tmux, driven by keys and read from its trace
- The Recovery on its partition is read from its trace on a virtio port. OCR reads only getty's login prompt, which must not flash by on **Start over**, and the language names of a published Recovery without trace in step 6
- Both runs must end with every test passed. The machine is then powered off hard instead of shut down, as after writing the Recovery: what a run reports as done must be on the disk
- The installed system unlocks its disk from a systemd credential and is reached over SSH as its account, by the key given to the Installer
- `START=desktop` installs the Desktop profile with the SSH server, boots it like step 2 and checks for GNOME's login screen and a systemd-oomd that watches swap and the session. The repair is the Core's
- Step 6 is skipped with a notice while no release of the series publishes a Recovery
- Step 6 writes the newest published Recovery, which may predate the Installer. Its language page then counts as started, since it reads no language the Installer left

**Note:** _Needs `qemu-base`, `edk2-ovmf`, `openssh`, `tesseract`, `tesseract-data-eng` and a network: the installation downloads its packages, step 6 the Recovery. Logs land in `dist/e2e/`, with a screenshot of the console where it stopped._

## Console

Both images boot with the same arguments, added by `build.sh`. Every other entry that starts Linux, such as the screen reader's, gets those from `nomodeset` on.

| Argument | Why |
| --- | --- |
| `quiet splash loglevel=3 …` | Plymouth instead of the boot log. **[➜ Silent boot](https://wiki.archlinux.org/title/Silent_boot)**. The reboot stays as quiet as on the installed system. **[➜ Kernel Parameters](../docs/REFERENCE.md#kernel-parameters)** |
| `plymouth.ignore-serial-consoles` | Plymouth falls back to text for good on a serial console, and every VM has one. Without it the Recovery boots in text mode under QEMU |
| `nomodeset` | Splash and interface draw on the firmware framebuffer, which needs no graphics driver. The ram disk carries none, and no driver can fail to bring up a screen |
| `systemd.condition_needs_update=0` | The build ran `ldconfig`, `sysusers` and `hwdb`, and a live image's `/usr` never changes. Without it they run again at every boot, before anything else. **[➜ systemd](https://www.freedesktop.org/software/systemd/man/latest/kernel-command-line.html)** |
| `fbcon=nodefer` | The console takes over the screen at boot. Taken over later, it appears only with the interface, and udev then sets it up at the same time |
| `vt.default_red=…` and its two siblings | The 16 console colors, so every console is Nord from the first frame. Plymouth restores the palette it found, so splash and interface share one background |

The interface uses color slots, filled with Nord by the palette. **[➜ Nord](https://www.nordtheme.com)**

| Slot | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Role | bezel | red | green | yellow | blue | magenta | cyan | white | gray | red+ | green+ | yellow+ | blue+ | magenta+ | cyan+ | white+ |
| Nord | 0 | 11 | 14 | 13 | 10 | 15 | 8 | 4 | dim | 11 | 14 | 13 | accent | 15 | 7 | 6 |

- Bezel: nord0, the splash background
- Gray: the interface's own dim, `#aeb5c3`, since nord3 is unreadable on nord0
- Bright blue: the accent, Arch blue lightened for nord0, `#45a9da`, as `console-accent` in `product.yaml` names it
- Blue: nord10, Nord's focus color, behind the row under the cursor, as `console-surface` names it. A console has only its first eight colors as backgrounds. The row reads in white+, since the accent on blue would not

## Console Glyphs

Each font has one glyph table, and a character outside it shows as a box. `font/glyphs.sh` builds the fonts as `build.sh` does and checks two things against every table:

- The files it gets: from `make check` the product, the catalogs, the library and every module file except READMEs and fastfetch's config, which target a graphical terminal
- The characters the interface draws itself: rules, cursor, the three cells of a QR code and the finished-run mark, and the runtime's own words, all listed by `arch-os glyphs`

The font is Terminus Bold in the size the kernel picks for its own font, as on a stock Arch ISO: 8×16, or 16×32 where 8×16 would give 22,000 cells or more. Full HD gets 16, four times that gets 32. Of the fonts in `kbd` and `terminus-font` it is the clean bold one with Latin, its accents, Greek and Cyrillic, at most 512 glyphs. It lacks ▀ and ▄ for QR codes, so `font/build.sh` adds them in two unused slots.

```
make glyphs-check
```

**Note:** _`make check` lints every script here and runs the check above. `make clean` removes `archiso/` and `download/` along with `dist/`._

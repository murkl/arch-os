# Reference

What Arch OS puts on a disk, and why. The scripts say *what*; this says *why*, so a comment never has to.

**Note:** _What a module's YAML may declare is the **[➜ Oak Reference](https://github.com/murkl/oak/blob/main/docs/REFERENCE.md)**. This file is about Arch Linux._

## Partitions

UEFI only, GPT, the whole disk in two partitions: Arch OS is the only system on it.

| Partition | Size | Type | Label | Mounted |
| --- | --- | --- | --- | --- |
| 1 | 1 GiB | EFI system (`ef00`) | `BOOT` | `/boot` |
| 2 | the rest | Linux (`8300`) | `BTRFS` | `/` |

Always in that order, and always btrfs. `/boot` is `fmask=0077,dmask=0077`: it holds the kernel and the signed image, root's business only.

- **Encryption**: LUKS2 on partition 2, opened as `cryptroot`. One password for disk, root and account
- **TRIM**: discards pass through the encryption, kept as a flag in the LUKS2 header (`--allow-discards --persistent`) rather than on the command line, so every opening passes them. dm-crypt drops them otherwise, and `fstrim.timer` trims nothing. What it gives away is which blocks are free, not what is in them. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Dm-crypt/Specialties#Discard/TRIM_support_for_solid_state_drives_(SSD))**

## Btrfs Subvolumes

| Subvolume | Mounted | Why it is its own |
| --- | --- | --- |
| `@` | `/` | The system. What a rollback replaces |
| `@home` | `/home` | Your files - a rollback must not touch them |
| `@snapshots` | `/.snapshots` | Where the snapshots live |
| `@log` | `/var/log` | Says *why* a rollback was needed |
| `@cache` | `/var/cache` | The package cache - large, and nothing reads it back |
| `@tmp` | `/var/tmp` | Scratch space, not worth restoring |
| `@libvirt` | `/var/lib/libvirt/images` | Virtual machine disks - rewritten all the time, so a snapshot would hold every old version of them, and a rollback would take them back |

A snapshot of `@` skips a subvolume mounted inside it, so a rollback keeps all seven untouched. Every installation gets the same layout, whether it runs virtual machines or not.

Mounted `defaults,noatime,compress=zstd`. Written once, in `oak.sh`, which both modules are given. The Recovery mounts whichever a disk actually has, so an older layout still opens.

**Note:** _`/var/tmp` is `chmod 1777` right after it is made, before systemd-tmpfiles would get to it. `/var/lib/libvirt/images` is `chattr +C` while it is still empty, so every disk image made there inherits it: copy-on-write breaks a file rewritten in place into countless fragments. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Btrfs#Disabling_CoW)**_

## The Kernel

`linux-zen`, on every installation. One kernel for everybody is one set of problems to know about, and a system that looks the same on every machine is one that can be helped the same way everywhere. It is tuned for a desktop that stays responsive under load.

## The Boot Chain

systemd-boot, `bootctl install`, one entry and one fallback. With **Secure Boot**, a **unified kernel image** per preset instead, signed with keys made for this machine.

`kernel_args` in `module.sh` is the one source of the command line - the unified image and systemd-boot read it whole.

The loader gets a boot entry in the firmware, first in its order. `bootctl` writes that one from the live system rather than from inside the new one: in a chroot it leaves the EFI variables alone, or, told to write them, cannot see the partition and writes an entry that points nowhere. Without an entry the firmware finds the loader only at `\EFI\BOOT\BOOTX64.EFI`, after every entry it already lists has been tried. The entries it still keeps for what the disk held before - a Windows Boot Manager, an earlier installation - are removed along with the old partitions; an entry for another disk stays.

The ram disk carries the processor's microcode itself (the `microcode` hook). Which package that is follows from the processor.

| Parameter | Why |
| --- | --- |
| `zswap.enabled=0` | Interferes with zram |
| `rd.luks.name=…=cryptroot` | Opens the disk in `sd-encrypt` |
| `rootflags=subvol=@ rootfstype=btrfs` | Which subvolume is root |
| `nowatchdog` | With Core tweaks: unused, delays shutdown |
| `quiet splash loglevel=3 …` | **[➜ Silent boot](https://wiki.archlinux.org/title/Silent_boot)** |
| `plymouth.ignore-serial-consoles` | A serial console makes Plymouth fall back to text, taking the passphrase prompt with it - every VM gets one unasked |

### Secure Boot

Offered only with **disk encryption**:

- No encryption, no point - the drive is readable either way
- A unified image signs kernel, initramfs and command line **as one**. Kernel-only leaves a forgeable initramfs on the unencrypted partition

Signed **last**: the NVIDIA driver and the boot splash rebuild the kernel image afterwards, bypassing pacman and `sbctl`'s hook. Every signed file is recorded, so the hook catches the next rebuild.

The keys are made **first**, with the boot images - before anything takes a snapshot. `/var/lib/sbctl` lives in `@`, so a snapshot from before the keys comes back unable to sign what it rebuilds, and with Secure Boot on the next kernel update would not start. The Recovery carries the keys over a rollback for the same reason: they belong to the firmware they are enrolled in, not to a point in time.

```mermaid
flowchart LR
    B["boot loader installed"] --> D["NVIDIA driver<br/>+ boot splash"]
    D -->|rebuild the kernel image| S["Secure Boot<br/>signs, last"]

    style S fill:#1793d1,stroke:#1793d1,color:#fff
```

`sbctl verify` lists `/boot/vmlinuz-*` as not signed, and that is how it is meant to be: the kernel reaches the firmware only inside the unified image. Signed on its own it would start from any entry somebody writes onto the unencrypted EFI partition, with a ram disk and a command line of their choosing.

Keys enroll only in **setup mode** - "Secure Boot disabled" is not that. `-m` keeps Microsoft's certificates. A failure here is only logged: the machine still boots.

**Note:** _systemd-boot's editor is off on every installation, signed or not - an editable command line is a root shell for whoever sits at the machine, past the password and past Secure Boot. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Systemd-boot#Loader_configuration)**_

**Note:** _Switching Secure Boot on is the firmware's own step - **[➜ installation step 5](README.md#5-switch-secure-boot-on)**._

### The Initial Ram Disk

```
base systemd keyboard autodetect microcode modconf kms sd-vconsole block [sd-encrypt] filesystems
```

- `kms` gives Plymouth a driver to draw on - without it, no splash
- `keyboard` before `autodetect`: every layout ships, not just the one plugged in while installing
- No `fsck`: the root is btrfs, whose `fsck` does nothing at boot

**Note:** _`/etc/mkinitcpio.conf.d/10-arch-os.conf`. Drop-ins after it build on it: the boot splash (`20-`), the NVIDIA driver (`30-`). The open drivers need none: the `kms` hook already puts them in the image. mkinitcpio's own pacman hook rebuilds the image whenever the NVIDIA module changes, built by DKMS or not - nothing here adds one._

## Tuning

Behind **Core tweaks**, changes behaviour, never what is installed. **[➜ Sysctl](https://wiki.archlinux.org/title/Sysctl)**

| Setting | Why |
| --- | --- |
| `vm.dirty_bytes=256M`, `_background_bytes=64M` | The default is a share of memory - gigabytes leaving in one burst. Bytes cap it to what the disk keeps up with |
| `vm.vfs_cache_pressure=50` | Directory/inode entries are cheap to keep, costly to look up again |
| `transparent_hugepage/defrag=defer+madvise` | Hands out pages immediately, defragments in the background |
| `DefaultTimeoutStopSec=15s` | The default 90s wait *is* what a hung shutdown looks like |
| `SystemMaxUse=200M` | The default keeps the journal forever on a modern disk |
| I/O schedulers | `bfq` for spinning disks, `mq-deadline` for SATA/eMMC, NVMe untouched - **[➜ wiki](https://wiki.archlinux.org/title/Improving_performance#Changing_I/O_scheduler)** |
| `tcp_congestion_control=bbr`, `default_qdisc=fq` | `cubic` reads any packet loss as congestion; wifi and long-distance links lose packets without being full. `bbr` measures delay instead |

Swap is **zram** always, tweaks or not. **[➜ Zram](https://wiki.archlinux.org/title/Zram)**

## Packages

Enough for a usable install, little enough that nothing needs looking after.

- `base`, `linux-zen`, `sudo`, `zram-generator`, `networkmanager`, `btrfs-progs`, `snapper`
- The processor's microcode, `intel-ucode` or `amd-ucode`, read off `/proc/cpuinfo`
- The chosen editor (`nano` unless another was picked), `man-db`, `man-pages`, `openssh` - `base` ships none of them
- Everything else follows an answer: the task that enables a service installs its package

**Firmware is skipped in a VM** - a guest's drivers are already in the kernel, and `linux-firmware` is over half the base install. Skipped unless a card is passed through.

**The graphics driver is read off the machine**, card by card, from sysfs - nothing to choose. Mesa always, and per vendor its Vulkan driver and video decoding. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Hardware_video_acceleration)**

| Card | Packages |
| --- | --- |
| Intel | `vulkan-intel`, `intel-media-driver` |
| AMD | `vulkan-radeon` - video decoding is part of Mesa |
| NVIDIA from Turing on (device ID `0x1e00` and up) | `nvidia-open-dkms` with the kernel headers, `nvidia-utils`, `libva-nvidia-driver`; `nvidia-prime` beside another card |
| NVIDIA before Turing | `vulkan-nouveau` - Arch ships no NVIDIA driver for those |
| A virtual machine's own adapter | Mesa alone |

The `lib32-` half of each comes with 32-bit support. NVIDIA's module is loaded early from the ram disk, and GDM's rule that turns Wayland off on it is overridden. **[➜ NVIDIA](https://wiki.archlinux.org/title/NVIDIA)**

**Virtual machines, both ways.** Inside one, the guest tools for its hypervisor are installed without a question. On real hardware, running virtual machines is a question of its own: libvirt, QEMU and a guest firmware, with the Virtual Machine Manager on a desktop. **[➜ Libvirt](https://wiki.archlinux.org/title/Libvirt)**

**Note:** _The GNOME group is filtered, not installed and trimmed: what the slim desktop drops is never downloaded._

**A desktop also gets `nss-mdns`** and the `mdns_minimal` module in front of the resolver in `/etc/nsswitch.conf`. Avahi announces this machine and finds the others either way; without that line nothing on the system can reach any of them by the `.local` name they answer to - a printer, a share and another machine are all `.local`. **[➜ Avahi](https://wiki.archlinux.org/title/Avahi#Hostname_resolution)**

**Note:** _File sharing announces itself under the hostname as it stands - `mdns name = mdns` in `smb.conf`. Samba's default is the NetBIOS name, which is the hostname in capitals, so the machine would be the one entry in a file manager's network list that shouts._

**Note:** _The public share is readable by any guest and writable only by the account the machine was installed with. A guest who may write is a folder anybody on the same network - a café's wifi included - can fill._

### The Firewall

`firewalld` rather than `ufw`: NetworkManager hands it a zone per connection, and libvirt, docker and podman each open their own ports in it. On a desktop `firewall-config` comes with it, the window the rules are kept in. **[➜ firewalld](https://wiki.archlinux.org/title/Firewalld)**

The default zone `public` lets in `ssh` and `dhcpv6-client`. Everything else is opened by the task that makes something listen:

| Service | Opened by | Why |
| --- | --- | --- |
| `mdns` | the desktop | Avahi's answers arrive as multicast, which no connection tracking matches to the question. Printers and shares stay invisible without it |
| `samba`, `ws-discovery-host` | file sharing | The share itself, and `wsdd`, without which Windows does not list the machine |

**Note:** _The SSH server changes nothing in `sshd_config`. Arch already refuses root a password login, and the account made here keeps one because it has no key yet._

**Note:** _Flatpak adds no remote: the package ships Flathub in `/usr/share/flatpak/remotes.d/`._

### Building from the AUR

| Limit | Value | Why |
| --- | --- | --- |
| Attempts | 3 | Retries downloads, not a stuck build |
| Timeout | 45 min | Past this it is stuck, not slow |
| Compile jobs | 1/GiB, capped at core count | More would run a live image out of memory |

One `timeout` around the whole build; passwordless `sudo` granted for its length and revoked after. What cargo downloads and caches lives in the build directory and is removed with it, rather than left in the new home. `!debug` is added to a PKGBUILD's own `options`, never put in their place - one that says `!lto` would otherwise be built without it.

Everything built from the AUR is **optional** in the run: `paru`, the boot splash theme and the Manager. The AUR can be out of reach for days, and nothing else in the system needs them - a failure is marked in the run and listed on the page it ends on rather than stopping it. Without its theme the boot splash draws Plymouth's own logo. **[➜ Oak Reference](https://github.com/murkl/oak/blob/main/docs/REFERENCE.md#tasks)**

**Note:** _With Core tweaks, `/etc/makepkg.conf.d/arch-os.conf` switches the debug package off, and nothing else: an AUR build otherwise leaves a second package beside the one that was wanted. `-march=native` is deliberately **not** there - it buys a few percent and pays for it with binaries that stop running the day the disk is moved, the image is restored onto other hardware or the CPU is replaced, and the crash that follows reads like failing memory._

**Note:** _Only `paru`, built from source against this machine's pacman. A `-bin` package is linked against the pacman of the day it was published and stops starting the day Arch moves `libalpm` - not offered here._

## Snapshots

Snapper on every installation: a snapshot before and after every package transaction via `snap-pac`, and nothing else. No timeline and no snapshot at every boot - between two transactions the system changes only where a snapshot should not follow, and a timeline would hold every old version of it: disk images, containers, databases. openSUSE's root configuration leaves the timeline off for the same reason. One timer, `snapper-cleanup.timer`, keeps the count down.

Snapper's defaults suit a slow-moving system, not a rolling release - fifty snapshots plus a year of timeline filled a disk to 70G against 35G of real system. So `NUMBER_LIMIT=10`, `NUMBER_LIMIT_IMPORTANT=5`, `TIMELINE_CREATE=no`, plus `ALLOW_GROUPS=wheel` and `SYNC_ACL=yes` so the group `/.snapshots` belongs to can read it - without them snapper answers nobody but root, whatever the directory says.

All of it in one place, `snapper_config` in `modules/installer/module.sh`: `set-config` takes one `KEY=VALUE` per argument, writes a whole line handed to it as one into the first key, and says nothing - so the task sets them from there and its test reads them back against the same list.

**Note:** _`snapper-cleanup.service` syncs on `ExecStopPost` - btrfs frees extents on its own schedule, and `df` lies until then._

### Rolling Back

**Only through the Recovery.** The kernel and its ram disk live on the EFI partition, which is not btrfs and is in no snapshot. A snapshot from before a kernel update brings back the modules of the old kernel while `/boot` keeps starting the new one, and the machine comes up without a single module. There is no stock way around that with systemd-boot, so no tool is installed that restores from the running desktop. The Recovery puts the snapshot in place and then rebuilds the boot files from the package cache - which is also why the download cache is never emptied outright, see `pacrc`.

## Closing the Target

`close_target`, shared by Installer and Recovery: swap off, sync, unmount, lock.

- `umount -R`, never `-A` - `-A` reaches beyond the target, and in the Recovery takes the rollback's snapshots with it
- `fuser -M` - without it, a non-mountpoint target resolves to the live image itself
- Whatever holds it is logged, then killed; the second unmount is left to fail for real

## Files a Task Ships

Every file a task writes into the new system lies in `data/` beside `task.sh`, named after the file it becomes, and is put in place with `render` from `module.sh` - `where` is that folder.

```
render "$(where)/main.conf" KERNEL="$KERNEL" CMDLINE="$cmdline" >"${MNT}/boot/loader/entries/main.conf"
```

- `{{NAME}}` is the only placeholder. It is filled from `NAME=value` handed to `render`, never from the environment
- `${HOME}`, `${PATH}`, `$(date …)` and every other `$` stay as they are, for the shell, systemd or pacman that reads the file later. Nothing has to be escaped
- A placeholder nobody filled, a value nothing asks for and a `{{` that opens no placeholder each fail the task
- Filled left to right and once: a value that holds `{{` is written as it is
- A file with nothing to fill goes through `render` as well, so a placeholder added later cannot reach a disk unfilled

Why not `envsubst`: it reads the environment, so every task-local value would have to be exported under a name somebody else may already read. It fills a variable that is not set with nothing and says nothing. And without a list of names it fills every `${…}`, including the ones that must stay; that list is a second copy of the template that nothing checks.

**Note:** _`make lint` refuses a `{ … } >"${MNT}/…"` block in any script, which is how these files were written before._

### Where there is no Drop-in

Where the program reads a directory, the file goes there. Four files have none, and are edited:

| File | Why |
| --- | --- |
| `/etc/pacman.conf` | One `Include =` line per file under `/etc/pacman.d/`, see `pacman_include`. A glob would stop pacman once it matched nothing |
| `/etc/locale.gen` | `locale-gen` reads nothing else, and a glibc update runs it again |
| `/etc/environment` | `pam_env` reads nothing else, and `sudo` takes its environment from there: `sudo visudo` then opens the chosen editor rather than a vi nobody installed |
| `/etc/nsswitch.conf` | glibc reads nothing else |

Two are written whole:

- `/etc/gdm/custom.conf`, only with autologin - which is behind disk encryption and nowhere else. GDM reads nothing else
- `/etc/xdg/reflector/reflector.conf`. `reflector.service` names it on its command line and in its sandbox, so moving it means restating both

**Note:** _`/etc/hosts` is not written. `filesystem` ships `localhost`, and `nss-myhostname` answers for the hostname._

## The Recovery

Two questions - keyboard, disk. Everything else is read, not asked:

| Read | How | When |
| --- | --- | --- |
| Root partition | Partition 2, when it is a LUKS container or a file system labelled `BTRFS` - what the Installer makes of it - or `ROOT`, the ext4 an earlier Installer offered | Before the run |
| Encryption | The LUKS header, no password needed | Before the run |
| File system | `lsblk` on the unlocked device | Once open |
| Subvolumes | `btrfs subvolume list` | While mounting |
| `/boot` | The installation's own `fstab` | While mounting |
| Kernels | `/usr/lib/modules/*/` | While rebuilding boot |
| Snapshots | `@snapshots` on the btrfs top level | Mid-run; none means the rollback step is skipped |

No network, ever - it may be what broke. Kernel images come from the package cache.

It repairs what earlier versions of the Installer made as well: another kernel, ext4, GRUB. What it finds on the disk is what it works with.

The password of an encrypted disk is typed once rather than twice: it already exists, and `cryptsetup` refuses a wrong one a second later and names the partition. A second box is for a password being chosen, which nothing can check until the system it belongs to boots.

**Note:** _A rollback builds the new `@` before touching the old one - a run that dies halfway leaves the system as found._

## The Boot Medium

A hybrid ISO already carries its partition table and boot paths - writing it is one raw copy.

- The image is the release `version:` in `oak.yaml` names
- Where it lands is asked: `XDG_DOWNLOAD_DIR` or `~/Downloads`. An image already there is used rather than fetched again
- It is checked against the checksum GitHub publishes for that release, and a mismatch discards it rather than keeping a broken one. The checksum is read once, when the image is fetched or found, and kept beside it as `.sha256`
- Where that release publishes no checksum, the run stops and asks before anything is written - an image built here is the one that arrives this way

**Root only for the write.** `as_root` wraps `umount`, `dd`, `partprobe` - nothing else. Everything else runs as you, so a live image never leaves root-owned files in your home.

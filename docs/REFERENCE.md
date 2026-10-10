# Reference

What Arch OS puts on a disk, and why. The scripts say *what*; this says *why*, so a comment never has to.

**Note:** _What a module's YAML may declare is the **[➜ Oak Reference](https://github.com/murkl/oak/blob/main/docs/REFERENCE.md)**. This file is about Arch Linux._

## Starting Arch OS

| From | How |
| --- | --- |
| The Arch OS ISO | Starts on its own. `installer` or `recovery` on another console (**Ctrl+Alt+F2**) |
| An official **[Arch Linux ISO](https://archlinux.org/download/)** | `curl -Ls https://bit.ly/archos \| bash` |
| Any other Linux | The same command, for **Create boot medium** |

- `--language=de` skips the language page: `… | bash -s -- --language=de`, or `installer --language=de`
- The release unpacks to `XDG_DOWNLOAD_DIR` or `~/Downloads`, `… | DOWNLOAD_DIR=<dir> bash` for another
- The live system takes the console keyboard and the time zone as they are answered, so what is typed and the log's times are right from there on. Only its `/etc/localtime` changes; the hardware clock is left alone

### Reusing Answers

Every answer lands in `installer.conf` as it is given, so an interrupted run resumes. A password never does.

- **Share:** from the page a finished run ends on, to **[paste.rs](https://paste.rs)**. The next installation starts from its code and asks only for the disk
- **Copy:** put `installer.conf` beside the Installer on another machine

## Partitions

UEFI only, GPT, the whole disk for Arch OS: it is the only system on it.

| Partition | Size | Type | Label | Mounted |
| --- | --- | --- | --- | --- |
| 1 | 1 GiB | EFI system (`ef00`) | `BOOT` | `/boot` |
| 2 | the rest | Linux (`8300`) | `BTRFS` | `/` |
| 3 | 1 GiB, twice its image, so an update has room | Linux (`8300`) | - | never - see **[The Recovery Partition](#the-recovery-partition)** |

Always in that order, and always btrfs. The third is there with **Recovery**, at the end of the disk, so the root is the second on every installation. `/boot` is `fmask=0077,dmask=0077`: it holds the kernel and the signed image, root's business only.

- **Encryption**: LUKS2 on partition 2, opened as `cryptroot`. The account's password, or with **Separate disk password** one of its own - see **[Accounts](#accounts)**
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

Mounted `defaults,noatime,compress=zstd`. Written once, in `oak.sh`, which both modules are given: the Installer lays every one of them down, and the Recovery opens only a disk that has every one of them.

**Note:** _`/var/tmp` is `chmod 1777` right after it is made, before systemd-tmpfiles would get to it. `/var/lib/libvirt/images` is `chattr +C` while it is still empty, so every disk image made there inherits it: copy-on-write breaks a file rewritten in place into countless fragments. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Btrfs#Disabling_CoW)**_

## The Kernel

`linux-zen`, on every installation. One kernel for everybody is one set of problems to know about, and a system that looks the same on every machine is one that can be helped the same way everywhere. It is tuned for a desktop that stays responsive under load.

## The Boot Chain

systemd-boot, `bootctl install`, one entry and one fallback, and the Recovery beside them. With **Secure Boot**, a **unified kernel image** per preset instead, signed with keys made for this machine.

The menu stays hidden: holding space while the machine starts brings it up. The entries carry `sort-key arch`, the key the signed images take from `os-release`, so they come before the Recovery, which carries its own.

`kernel_args` in the bootloader task is the one source of the command line - the unified image and systemd-boot read it whole.

The loader gets a boot entry in the firmware, first in its order. `bootctl` writes that one from the live system rather than from inside the new one: in a chroot it leaves the EFI variables alone, or, told to write them, cannot see the partition and writes an entry that points nowhere. Without an entry the firmware finds the loader only at `\EFI\BOOT\BOOTX64.EFI`, after every entry it already lists has been tried. The entries it still keeps for what the disk held before - a Windows Boot Manager, an earlier installation - are removed along with the old partitions; an entry for another disk stays.

The ram disk carries the processor's microcode itself (the `microcode` hook). Which package that is follows from the processor.

| Parameter | Why |
| --- | --- |
| `zswap.enabled=0` | Interferes with zram |
| `rd.luks.name=…=cryptroot` | Opens the disk in `sd-encrypt` |
| `rootflags=subvol=@ rootfstype=btrfs` | Which subvolume is root |
| `nowatchdog` | With Core tweaks: unused, delays shutdown |
| `quiet splash loglevel=3 …` | **[➜ Silent boot](https://wiki.archlinux.org/title/Silent_boot)**. `vt.global_cursor_default=0` hides the cursor on every console, so `/etc/issue.d/cursor.issue` shows it again before each login |
| `plymouth.ignore-serial-consoles` | A serial console makes Plymouth fall back to text, taking the passphrase prompt with it - every VM gets one unasked |

### Secure Boot

Offered only with **disk encryption**:

- No encryption, no point - the drive is readable either way
- A unified image signs kernel, initramfs and command line **as one**. Kernel-only leaves a forgeable initramfs on the unencrypted partition

Signed **last**: the NVIDIA driver and the boot splash rebuild the kernel image afterwards, bypassing pacman and `sbctl`'s hook. Every signed file is recorded, so the hook catches the next rebuild. The Recovery's image is signed with them, so it starts with Secure Boot on.

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

#### Switching It On

After the first start, where it was left on in **Setup**:

| `sbctl status` says | Do |
| --- | --- |
| `✓` | Restart, switch Secure Boot on in the firmware |
| `✗` | Clear the Secure Boot keys in the firmware (setup mode), then `sudo sbctl enroll-keys -m`, restart, switch it on |

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
| `DefaultTimeoutStopSec=15s`, for the session's own services | The default 90s wait *is* what a hung logout looks like. System services keep systemd's default: a database, a container or a virtual machine that takes its time is writing something down, and cutting it short is what loses it |
| `SystemMaxUse=200M` | The default keeps the journal forever on a modern disk |
| I/O scheduler | `bfq` for spinning disks, which keeps a desktop responsive while one seeks. Everything else as the kernel picks it: `mq-deadline` for a single queue, none for NVMe - **[➜ wiki](https://wiki.archlinux.org/title/Improving_performance#Changing_I/O_scheduler)** |
| `strict_limit=1`, `max_ratio=10` for USB drives | A stick writes 256M far slower than an internal disk: a copy finishes into memory, the file manager shows little or no progress, and the eject waits for the rest. A tenth of the limit, about 25M, holding from the first byte rather than only past the global background limit. A ratio, because `max_bytes` is kept as one too, taken of whatever the limit is when the drive is plugged in - **[➜ kernel](https://docs.kernel.org/admin-guide/abi-testing.html#abi-sys-class-bdi-bdi-strict-limit)** |
| `tcp_congestion_control=bbr`, `default_qdisc=fq` | `cubic` reads any packet loss as congestion; wifi and long-distance links lose packets without being full. `bbr` measures delay instead |

Swap is **zram** always, tweaks or not. **[➜ Zram](https://wiki.archlinux.org/title/Zram)**

## Accounts

One account, in `wheel`, with `sudo`. Root keeps the `*` Arch ships, so nothing logs in as root: a password for it would only be a second way to the same rights. systemd's emergency shell does not open without one either, and the **[Recovery](#the-recovery)** is the way into a system that no longer starts.

- **One password** unlocks the disk and logs you in
- **Separate disk password** gives the disk one of its own. The login screen asks for yours, and every account has its own: the setup for a shared machine

Automatic login only behind disk encryption with one password. `pam_gdm` hands the passphrase typed at boot to the keyring, so the keyring has to carry the disk password, and only with one password is that the account's as well. With **Separate disk password** the login asks, and the keyring carries the account password. **[➜ Arch Wiki](https://wiki.archlinux.org/title/GNOME/Keyring#PAM_step)**

### The Keyring

Where the keyring's password and the login's differ, it asks after the login. **Passwords and Keys** puts it right, once installed with `sudo pacman -S seahorse`: **Login** ➜ **Change Password**.

| After | Set the keyring's password to |
| --- | --- |
| Changing the disk password, with automatic login | The new disk password |
| Changing the account password, logging in with it | The new account password |
| Switching automatic login on, with a separate disk password | The disk password |
| Switching automatic login off, with two different passwords | The account password |

The disk password belongs to the partition `lsblk -f` lists as `crypto_LUKS`: `sudo cryptsetup luksChangeKey /dev/<partition>`.

### More Accounts

- **At installation:** **Separate disk password**. No automatic login, and the login screen lists every account
- **Afterwards:** **Settings ➜ System ➜ Users ➜ Add User**. **Parental Controls** there limits a standard account, and comes with **Flatpak**
- **On the text console:** `sudo useradd -m <name>`, then `sudo passwd <name>`

**Note:** _On a shared machine with one password, switch automatic login off in **Settings ➜ System ➜ Users**. What Arch OS sets up at the first login is for the account it installed._

## Packages

Enough for a usable install, little enough that nothing needs looking after.

- `base`, `linux-zen`, `mkinitcpio`, `sudo`, `zram-generator`, `networkmanager`, `btrfs-progs`, `snapper`
- The processor's microcode, `intel-ucode` or `amd-ucode`, read off `/proc/cpuinfo`
- The chosen editor (`nano` unless another was picked), `man-db`, `man-pages`, `openssh` - `base` ships none of them. The editor gets a configuration of its own - see [The Text Editor](#the-text-editor)
- Everything else follows an answer: the task that enables a service installs its package

**A wireless network joined in the Installer comes along.** Each one iwd knows on the live system becomes a NetworkManager connection, so the first boot is online. A network with 802.1X is joined again on the new system.

**Firmware is skipped in a VM** - a guest's drivers are already in the kernel, and `linux-firmware` is over half the base install. Skipped unless a card is passed through.

**The graphics driver is read off the machine**, card by card, from sysfs - nothing to choose. Mesa always, and beside it what games reach for: `vkd3d` for Direct3D 12 under Wine, `mesa-utils` and `vulkan-tools` to see which card a program ended up on. Per vendor its Vulkan driver and video decoding. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Hardware_video_acceleration)**

| Card | Packages |
| --- | --- |
| Intel | `vulkan-intel`, `intel-media-driver` |
| AMD | `vulkan-radeon`, `vulkan-mesa-layers`, `opencl-mesa` - video decoding is part of Mesa |
| NVIDIA from Turing on (device ID `0x1e00` and up) | `nvidia-open-dkms` with the kernel headers, `nvidia-utils`, `nvidia-settings`, `opencl-nvidia`, `libva-nvidia-driver`; `nvidia-prime` beside another card |
| NVIDIA before Turing | `vulkan-nouveau` - Arch ships no NVIDIA driver for those |
| A virtual machine's own adapter | Mesa alone |

The `lib32-` half of each comes with 32-bit support. NVIDIA's module is loaded early from the ram disk, and GDM's rule that turns Wayland off on it is overridden. **[➜ NVIDIA](https://wiki.archlinux.org/title/NVIDIA)**

**Virtual machines, both ways.** Inside one, the guest tools for its hypervisor are installed without a question. On real hardware, running virtual machines is a question of its own: libvirt, QEMU and a guest firmware, with the Virtual Machine Manager on a desktop. **[➜ Libvirt](https://wiki.archlinux.org/title/Libvirt)**

**Note:** _The GNOME group is filtered, not installed and trimmed: what the slim desktop drops is never downloaded, and GNOME Web is never taken from it - it is one answer to the browser question. What a member it keeps still needs arrives all the same and stays out of the app grid: Papers, behind the previews in Files. **GNOME Software** installs Flatpaks and, with `fwupd` from the desktop extras, firmware updates. It installs no packages: Arch builds Software with its PackageKit plugin switched off, and PackageKit is [not recommended](https://wiki.archlinux.org/title/Pacman/Tips_and_tricks#Graphical), so none is installed and pacman stays the one thing that changes the system._

**Note:** _Extensions are found and installed on **[extensions.gnome.org](https://extensions.gnome.org)**, through `gnome-browser-connector` from the desktop extras, and switched on and off in the **Extensions** app, `gnome-extensions-app`. **[➜ Extensions](https://wiki.archlinux.org/title/GNOME#Extensions)**_

**The browser follows the system language.** Firefox gets the language pack `firefox-i18n-<lang>`, Firefox and GNOME Web the `hunspell-<lang>` dictionary, each looked up from the locale - region first, then language - and left out where Arch has none. GNOME Web also gets the GStreamer plugins WebKit plays media through, and Vivaldi `vivaldi-ffmpeg-codecs` for H.264 and AAC, from the repositories rather than the library it would otherwise download into the home. Nothing else is set, because nothing else is needed: Arch's Firefox already follows the system language, reads the system's dictionaries and never asks to be the default, Chromium and Vivaldi carry every language and fetch their own dictionaries, and Chromium has run on Wayland and decoded video on the card by itself since versions 140 and 143. The chosen one opens every web link and HTML file - set with `gio mime` - and stands on the dock. **[➜ Firefox](https://wiki.archlinux.org/title/Firefox)** · **[➜ Chromium](https://wiki.archlinux.org/title/Chromium)**

**A desktop also gets `nss-mdns`** and the `mdns_minimal` module in front of the resolver in `/etc/nsswitch.conf`. Avahi announces this machine and finds the others either way; without that line nothing on the system can reach any of them by the `.local` name they answer to - a printer, a share and another machine are all `.local`. **[➜ Avahi](https://wiki.archlinux.org/title/Avahi#Hostname_resolution)**

**Note:** _File sharing announces itself under the hostname as it stands - `mdns name = mdns` in `smb.conf`. Samba's default is the NetBIOS name, which is the hostname in capitals, so the machine would be the one entry in a file manager's network list that shouts._

**Note:** _The public share is readable by any guest and writable only by the account the machine was installed with. A guest who may write is a folder anybody on the same network can fill._

### The Firewall

`firewalld` rather than `ufw`: NetworkManager hands it the zone of every connection, and libvirt, docker and podman each open their own ports in it. Nothing to look after: two zones carry the whole policy, and nothing is installed to change it - `firewall-config` or any other front end goes on top if wanted. **[➜ firewalld](https://wiki.archlinux.org/title/Firewalld)**

| Zone | Where | Lets in |
| --- | --- | --- |
| `public` | Every network nobody has marked - the default zone | `dhcpv6-client`; `mdns` on a desktop; `ssh` with the SSH server |
| `home` | A network marked as trusted | What firewalld ships it with (`ssh`, `mdns`, `samba-client`, `dhcpv6-client`); `samba` and `ws-discovery-host` with file sharing |

No machine can tell a café's wifi from the one at home, so no network is trusted until somebody says so - once per network, and NetworkManager remembers it:

```
nmcli connection modify <name> connection.zone home
```

At home the router already stands between this machine and the internet, and what is left to keep out is the neighbours - which is why `home` may let in what a café's wifi must not reach. Everything is opened by the task that makes something listen, in the zone it belongs in:

| Service | Opened by | Why |
| --- | --- | --- |
| `mdns` | the desktop, in `public` | Avahi's answers arrive as multicast, which no connection tracking matches to the question. Printers and shares stay invisible without it. It gives away nothing avahi does not announce by itself |
| `ssh` | the SSH server, in `public` | Logging in from another machine is what was asked for, wherever that machine is. firewalld's own `public` lets it in whether anything listens or not |
| `samba`, `ws-discovery-host` | file sharing, in `home` | The share itself, and `wsdd`, without which Windows does not list the machine. A share on a café's wifi is a password anybody there can try |

**Note:** _The SSH server changes nothing in `sshd_config`. Arch already refuses root a password login, and the account made here keeps one because it has no key yet._

**Note:** _Flatpak adds no remote: the package ships Flathub in `/usr/share/flatpak/remotes.d/`._

### Building from the AUR

| Limit | Value | Why |
| --- | --- | --- |
| Attempts | 3 | Retries downloads, not a stuck build |
| Timeout | 45 min | Past this it is stuck, not slow |
| Compile jobs | 1/GiB, capped at core count | More would run a live image out of memory |

One `timeout` around the whole build; passwordless `sudo` granted for its length and revoked after. What cargo downloads and caches lives in the build directory and is removed with it, rather than left in the new home. `!debug` is added to a PKGBUILD's own `options`, never put in their place - one that says `!lto` would otherwise be built without it.

Everything built from the AUR is `allow-failure` in the run: `paru`, the boot splash theme and the Manager. The AUR can be out of reach for days, and nothing else in the system needs them - a failure is counted and listed under **Test results** rather than stopping the run. Without its theme the boot splash draws Plymouth's own logo. **[➜ Oak Reference](https://github.com/murkl/oak/blob/main/docs/REFERENCE.md#tasks)**

**Note:** _With Core tweaks, `/etc/makepkg.conf.d/arch-os.conf` switches the debug package off, and nothing else: an AUR build otherwise leaves a second package beside the one that was wanted. `-march=native` is deliberately **not** there - it buys a few percent and pays for it with binaries that stop running the day the disk is moved, the image is restored onto other hardware or the CPU is replaced, and the crash that follows reads like failing memory._

**Note:** _Only `paru`, built from source against this machine's pacman. A `-bin` package is linked against the pacman of the day it was published and stops starting the day Arch moves `libalpm` - not offered here._

### The Text Editor

Whichever is chosen gets a small configuration in root's home and in the account's - never in `/etc`, which belongs to the package. What the editor ships with and nothing else: no plugins, no plugin manager, nothing to update but the package.

| Editor | File | Theme | Beyond its own defaults |
| --- | --- | --- | --- |
| `nano` | `~/.config/nano/nanorc` | The terminal's own palette, Arch blue on the bar | Line numbers, the minibar and a scroll indicator, the mouse, auto-indent, tabs of 4, erasing what is marked, soft wrap at a word, the cursor where it was left. Highlighting from `nano-syntax-highlighting` |
| `vim` | `~/.vim/vimrc` | `habamax`, Vim's own | `defaults.vim` kept, line numbers, a status line, 4 spaces for a tab, smart-case search lit where it matched |
| `neovim` | `~/.config/nvim/init.lua` | Neovim's own default | Line numbers, 4 spaces for a tab, smart-case search, an undo that survives closing the file |
| `micro` | `~/.config/micro/settings.json` | `atom-dark` | 4 spaces for a tab, changes marked in the gutter, the cursor and the undo kept, folders created on save |
| `helix` | `~/.config/helix/config.toml` | `nord`, the palette the console and the prompt are drawn in | The current line and the mode shown in colour, a bar cursor while typing, open files as tabs, indent guides, soft wrap |

**Note:** _`~/.vim/vimrc` rather than `~/.config/vim/vimrc`: Vim reads the second only where `XDG_CONFIG_HOME` is set, which a desktop leaves to the user._

## Snapshots

Snapper on every installation: a snapshot before and after every package transaction via `snap-pac`, and nothing else. No timeline and no snapshot at every boot - between two transactions the system changes only where a snapshot should not follow, and a timeline would hold every old version of it: disk images, containers, databases. openSUSE's root configuration leaves the timeline off for the same reason. One timer, `snapper-cleanup.timer`, keeps the count down.

Snapper's defaults suit a slow-moving system, not a rolling release - fifty snapshots plus a year of timeline filled a disk to 70G against 35G of real system. So `NUMBER_LIMIT=10`, `NUMBER_LIMIT_IMPORTANT=5`, `TIMELINE_CREATE=no`, plus `ALLOW_GROUPS=wheel` and `SYNC_ACL=yes` so the group `/.snapshots` belongs to can read it - without them snapper answers nobody but root, whatever the directory says.

All of it in one place, `data/settings` beside the snapper task: `set-config` takes one `KEY=VALUE` per argument, writes a whole line handed to it as one into the first key, and says nothing - so the task sets them from there and its test reads them back against the same list.

**Note:** _`snapper-cleanup.service` syncs on `ExecStopPost` - btrfs frees extents on its own schedule, and `df` lies until then._

### Rolling Back

**Only through the Recovery.** The kernel and its ram disk live on the EFI partition, which is not btrfs and is in no snapshot. A snapshot from before a kernel update brings back the modules of the old kernel while `/boot` keeps starting the new one, and the machine comes up without a single module. There is no stock way around that with systemd-boot, so no tool is installed that restores from the running desktop. The Recovery puts the snapshot in place and then rebuilds the boot files from the package cache - which is also why the download cache is never emptied outright, see `pacrc`.

## Closing the Target

Swap off, sync, unmount, lock: in the Installer before the disk is partitioned, in the Recovery before it is opened - a second attempt starts from whatever the first left. A restart or a shutdown leaves it to systemd, which unmounts and locks on the way down.

- `umount -R`, never `-A` - `-A` reaches beyond the target, and in the Recovery takes the rollback's snapshots with it
- `fuser -M` - without it, a non-mountpoint target resolves to the live image itself
- Whatever holds it is logged, then killed; the second unmount is left to fail for real

## Files a Task Ships

Every file a task writes into the new system lies in `data/` beside `task.sh`, named after the file it becomes, and is put in place with `render` from `oak.sh` - `where` is that folder.

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

- `/etc/gdm/custom.conf`, only with autologin - which is behind disk encryption with one password and nowhere else. GDM reads nothing else
- `/etc/xdg/reflector/reflector.conf`. `reflector.service` names it on its command line and in its sandbox, so moving it means restating both

**Note:** _`/etc/hosts` is not written. `filesystem` ships `localhost`, and `nss-myhostname` answers for the hostname._

## The Recovery

- From its partition: **Arch OS Recovery** in the boot menu, or **Recovery** among the applications. It starts with Secure Boot on
- From the ISO: `recovery` on another console (**Ctrl+Alt+F2**). Secure Boot off to boot it, on again afterwards

Two questions - keyboard, disk - and on its own partition not even those, see below. Everything else is read, not asked:

| Read | How | When |
| --- | --- | --- |
| Root partition | Partition 2, when it is a LUKS container or a btrfs labelled `BTRFS` - what the Installer makes of it | Before the run |
| Encryption | The LUKS header, no password needed | Before the run |
| File system | `lsblk` on the unlocked device - btrfs, or it is turned away | Once open |
| Subvolumes | `btrfs subvolume list` on the top level - every one of the layout, or it is turned away | Once open |
| `/boot` | Partition 1, as the Installer lays it out - not the `fstab`, which may be what broke | While mounting |
| Kernels | `/usr/lib/modules/*/` | While rebuilding boot |
| Snapshots | `@snapshots` on the btrfs top level | Mid-run; none means the rollback step is skipped |

No repair needs a network - the network may be what broke, and kernel images come from the package cache. **Configure Wi-Fi** in its **Setup** joins one all the same, for an update of the Recovery or whatever somebody wants to fetch in the shell, wherever the machine has a card and no internet over a cable. On its own partition a cable comes up at boot and is preferred while both are up, and the wireless daemon starts once there is a card to ask it about; nothing else of the network runs.

It repairs what the Installer of its release series makes: `linux-zen`, btrfs with the whole subvolume layout, systemd-boot.

The password of an encrypted disk is typed once rather than twice: it already exists, and it is tried on the disk right where it is typed - `cryptsetup open --test-passphrase`, which opens nothing - so a wrong one is refused on that page. A second box is for a password being chosen, which nothing can check until the system it belongs to boots.

What the Recovery starts with on its own partition is put in force before the first page: the keyboard is loaded, and one that will not load is asked for again rather than left standing, since the password is typed next.

**Note:** _A rollback builds the new `@` before touching the old one, and the next run finishes one cut short between the two - a run that dies halfway never leaves a system without `@`._

### The Recovery Partition

The Recovery of the release that installed the system, or a newer one of its series, on a partition of its own at the end of the disk and in the boot menu as **Arch OS Recovery**. It is the one that knows this layout, and it needs neither a USB stick nor a network to start. With **Recovery** off there is none - the ISO opens the system all the same.

It is built with the release rather than on the machine, out of Arch's own minimal profile `baseline`: the kernel, `base`, `btrfs-progs`, `arch-install-scripts`, Plymouth and the Recovery module, and `iwd` with the firmware of the wireless cards. No editor, and nothing it starts but the Recovery and a cable's network - the wireless daemon only once there is a card; manuals, translations, headers, the graphics drivers and whatever the firmware packages carry for graphics, cameras and Bluetooth are left out as the packages go in. A pre-release ISO carries it ready-made. A release's ISO leaves it out, which keeps the ISO under the 2 GiB GitHub takes for a file, and its Installer fetches it like every other live image does: from the release the Installer belongs to - `arch-os-X.Y.Z-recovery-x86_64.tar`, held to the checksum GitHub publishes for it - into `/tmp`, before the disk is touched. Either way the Installer only writes it:

| File | Goes to | What it is |
| --- | --- | --- |
| `recovery.efi` | `/boot/EFI/Linux/arch-os-recovery.efi` | Kernel, ram disk and command line as one image. systemd-boot lists it by itself, under the name its `os-release` gives it |
| `recovery.img` | partition 3, byte for byte | A read-only erofs holding the root file system and its signature. The running system never mounts it, nothing but an update writes to it, and the file manager does not list it |

How it starts:

1. The boot loader starts the image - with Secure Boot, signed with the machine's own keys like the system's own
2. The ram disk finds the partition by the UUID its command line names, made for each build, so no other disk is taken for it
3. It checks the root file system against a certificate it carries itself. The key that signed it was made for the build and thrown away with it, so nothing on the partition starts that the build did not make, and a damaged one stops at a prompt that says so. Valid from 1970 to 9999: a machine whose clock battery died is still one to repair
4. It copies the root file system to memory, so nothing of the disk is held while the Recovery works on it, and starts it
5. Plymouth on the screen the firmware set up - `nomodeset`, so no graphics driver and no firmware for one, and `plymouth.ignore-serial-consoles` like the system's own - and the Recovery on tty1
6. The Recovery reads what the Installer left it on the EFI partition - `EFI/arch-os-recovery/`, read-only and unmounted again at once - and works out its disk as the one holding the partition it was started from. So it opens straight on its menu, in the language the Installer was read in and on the keyboard it was typed on

It is a kiosk: the Recovery is the only thing the machine runs, and nothing leads to a prompt. Its unit holds tty1 and never hands it back, and no other console has a login. Leaving it is **Exit**, as on the ISO, and its systemd unit starts it again on every answer it had: what the Installer left is handed over once a boot. A crash is started again the same way: the first thing a run does is close whatever the last one left open. The shell inside the repaired system is a row on the page the repair ends on, behind the disk's password where there is one.

**Note:** _The EFI partition is not signed, so what the Recovery reads there is held to the same patterns and lists as any answer read from a file - the worst a changed file can do is ask a question again._

**Note:** _`systemctl reboot --boot-loader-entry=arch-os-recovery.efi` starts it once from the running system. On a desktop that is **Recovery** among the applications: one yes or no, then the restart, and logind lets whoever sits at the machine do it without a password. The question is the launcher's own, in English or German by the session's language; its buttons are zenity's._

#### Updating It

**Update the Recovery** in its **Setup**, on its partition only. It looks at the latest release on GitHub first and says so where there is nothing newer; a newer one is installed after a question that opens on No.

- Only within the release series: 2.0.0 takes 2.4.1, never 3.0.0. A new major version may lay a system down differently, which its Recovery would not repair
- Everything that can fail comes before the partition is touched: the download held to the checksum GitHub publishes, its size to the partition, and with Secure Boot on the image the loader starts signed with the system's own keys. Those lie in the opened system, so the disk's password is asked for that
- Then the partition, read back against the download, and the boot image moved over the old one. The two disagree only for the length of the write: a machine that loses power right then starts the system as before, and its Recovery only once the partition is written again
- The partition is the same one: the file manager keeps passing over it, by its partition UUID, which the update leaves alone

**Note:** _Without disk encryption, whoever sits at the machine can open the system from it - as from any USB stick, or by taking the disk out. Encryption is what closes that: the Recovery asks for the password like everything else._

## The Boot Medium

A hybrid ISO already carries its partition table and boot paths - writing it is one raw copy.

- The image is the release `version:` in `oak.yaml` names
- Where it lands is asked: `XDG_DOWNLOAD_DIR` or `~/Downloads`. An image already there is used rather than fetched again
- The device is asked each time **Start** is chosen, before the password, and never kept: a path like `/dev/sdb` only names a stick while it is plugged in
- It is checked against the checksum GitHub publishes for that release, and a mismatch discards it rather than keeping a broken one. The checksum is read once, when the image is fetched or found, and kept beside it as `.sha256`
- Where that release publishes no checksum, nothing is written. **Verify checksum** off in **Setup** writes the image in the folder as it is, without asking the release anything - an image built here is the one that arrives this way

**Root only for the write.** `as_root` wraps `umount`, `dd`, `blockdev` - nothing else. Everything else runs as you, so a live image never leaves root-owned files in your home. Where `sudo` wants a password, it is asked in the interface right before the run, tried with `sudo` there, and handed to it on stdin - the screen is never handed to a prompt, and the write shows how far `dd` has got under its step.

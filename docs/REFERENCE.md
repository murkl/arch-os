# Reference

What Arch OS puts on a disk, and why. The scripts show *what*. This file explains *why*, so the code needs few comments.

**Note:** _What a module's YAML can declare is in the **[➜ Oak Reference](https://github.com/murkl/oak/blob/main/docs/REFERENCE.md)**. This file is about Arch Linux._

## Starting Arch OS

| From | How |
| --- | --- |
| The Arch OS ISO | Starts by itself. `installer` or `recovery` on another console (**Ctrl+Alt+F2**) |
| An official **[Arch Linux ISO](https://archlinux.org/download/)** | `curl -Ls https://bit.ly/archos \| bash` |
| Any other Linux | The same command, for **Create boot medium** |

- `--language=de` skips the language page: `… | bash -s -- --language=de`, or `installer --language=de`
- The release unpacks to `XDG_DOWNLOAD_DIR` or `~/Downloads`. `… | DOWNLOAD_DIR=<dir> bash` picks another folder
- The live system switches to the console keyboard and the time zone as soon as you answer them, so typing and the log's times are right from then on. Only its `/etc/localtime` changes, the hardware clock stays as it is

### Reusing Answers

Every answer lands in `installer.conf` as soon as you give it, so an interrupted run resumes. Passwords never do.

- **Share:** the page a finished run ends on uploads the answers to **[paste.rs](https://paste.rs)**. The next installation starts from that code and asks only for the disk
- **Copy:** put `installer.conf` beside the Installer on another machine

A shared configuration leaves out the disk and the kernel parameters. Both belong to the machine they were given on, and kernel parameters from a stranger's code could open a root shell at boot.

## Partitions

UEFI only, GPT, and the whole disk: Arch OS is the only system on it.

| Partition | Size | Type | Label | Mounted |
| --- | --- | --- | --- | --- |
| 1 | 1 GiB | EFI system (`ef00`) | `BOOT` | `/boot` |
| 2 | the rest | Linux x86-64 root (`8304`) | `BTRFS` | `/` |
| 3 | 1 GiB, twice its image, so an update has room | Linux (`8300`) | - | never, see **[The Recovery Partition](#the-recovery-partition)** |

The order is fixed and the file system is always btrfs. The root's type is the one the **[➜ Installation guide](https://wiki.archlinux.org/title/Installation_guide#Example_layouts)** uses, so systemd's tools find it by its type. The third partition exists only with **Recovery** on and sits at the end of the disk, so the root is the second partition on every installation. `/boot` is mounted with `fmask=0077,dmask=0077`: it holds the kernel and the signed images, which are for root alone.

- **Encryption:** LUKS2 on partition 2, opened as `cryptroot`. It takes the account's password, or with **Separate disk password** one of its own, see **[Accounts](#accounts)**
- **TRIM:** discards pass through the encryption. The flag lives in the LUKS2 header (`--allow-discards --persistent`), so every unlock passes them without a kernel parameter. Without it dm-crypt drops them and `fstrim.timer` trims nothing. It reveals which blocks are free, not what is in them. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Dm-crypt/Specialties#Discard/TRIM_support_for_solid_state_drives_(SSD))**

## Btrfs Subvolumes

| Subvolume | Mounted | Why it is separate |
| --- | --- | --- |
| `@` | `/` | The system. A rollback replaces it |
| `@home` | `/home` | Your files, which a rollback must not touch |
| `@snapshots` | `/.snapshots` | Where the snapshots live |
| `@log` | `/var/log` | Shows *why* a rollback was needed |
| `@cache` | `/var/cache` | The package cache: large, and never read back |
| `@tmp` | `/var/tmp` | Scratch space, not worth restoring |

A snapshot of `@` leaves out every subvolume mounted inside it, so a rollback keeps all six as they are.

All are mounted with `defaults,noatime,compress=zstd`. The layout is written once, in `oak.sh`, which both modules load: the Installer creates every subvolume, and the Recovery opens only a disk that has all of them.

**Note:** _`/var/tmp` gets `chmod 1777` right after it is created, before systemd-tmpfiles runs._

**Note:** _An installation of 2.0 also has `@libvirt` at `/var/lib/libvirt/images`. The Recovery opens it all the same: it checks for every subvolume of this layout and leaves any other alone._

## The Kernel

`linux-zen`, on every installation. One kernel for everybody means one set of problems to know, and a system that looks the same everywhere can be helped the same way everywhere. It is tuned for a desktop that stays responsive under load.

## The Boot Chain

systemd-boot, installed with `bootctl install`, with two entries for the system and the Recovery beside them. With **Secure Boot** each entry starts a **unified kernel image** instead, signed with keys made for this machine. The images live in `/boot/EFI/arch-os/`, because in `EFI/Linux` the loader would list each a second time, beside the entry that counts its tries.

The menu stays hidden. Hold space while the machine starts to bring it up. systemd-boot listens for the key only briefly, and a firmware that passes no key on, such as a laptop keyboard it initialises late, never shows the menu. That is why the Recovery also has an entry in the firmware's own boot menu, on firmware that lists entries outside its boot order. The system's entries carry `sort-key arch` and `arch-fallback`, so they come first and in that order. The Recovery sorts by its own `os-release` ID.

`kernel_args` in the bootloader task is the one source of the command line. The unified image and the systemd-boot entries both use it unchanged.

### When the System Does Not Start

The loader tries each system entry three times before it moves on: first the system, then its fallback, then the Recovery. After three failed starts the fallback image comes up, which carries every kernel module. After three more the Recovery starts, without a key press, a USB stick or a network. **[➜ Automatic Boot Assessment](https://systemd.io/AUTOMATIC_BOOT_ASSESSMENT/)**

| Step | What happens |
| --- | --- |
| Start | systemd-boot takes one try off the entry it starts: `main+3.conf` becomes `main+2-1.conf` |
| A good start | The disk is unlocked and mounted, and on a Desktop the login screen or the session it logs into is up (`boot-complete.target`). `systemd-bless-boot` marks the entry good, and `arch-os-boot-tries.service` gives both entries their three tries back |
| No tries left | `main+0-3.conf` sorts behind every other entry, and the loader starts the next one |
| The Recovery | Gives both entries their tries back as it starts, so the next start tries the system again |

- `loader.conf` sets no `default`: the loader would start a default however often it failed. The Installer and the Recovery clear a default an earlier system left in the firmware
- A start that is cut short counts as failed. Switch the machine off at the password prompt three times, and the next start uses the fallback. Three more, and it uses the Recovery. Leaving the Recovery gives the system its tries back
- A kernel panic restarts the machine after 10 seconds (`panic=10`), so a system that panics on every start reaches the Recovery by itself
- On a Desktop, `arch-os-session-up.service` waits up to 5 minutes for the session on the screen. A start without one does not count as good, though the machine keeps running. The next restart uses the next try
- An installation of 2.0 starts its image as the loader's default and counts nothing. **Rebuild the boot files** in the Recovery lays it out as this release does: it moves and signs the images in `/boot/EFI/arch-os/`, writes the entries, drops the default and removes the old images last

The loader also gets an entry in the firmware, first in the boot order. `bootctl` writes it from the live system, not from inside the new one. In a chroot it leaves the EFI variables alone, or, when told to write them, cannot see the partition and writes an entry that points nowhere. Without an entry the firmware finds the loader only at `\EFI\BOOT\BOOTX64.EFI`, after it has tried every entry it already lists. Entries left over from what the disk held before, such as a Windows Boot Manager or an earlier installation, are removed with the old partitions. An entry for another disk stays.

The initial ram disk carries the processor's microcode (the `microcode` hook). The package follows from the processor.

| Parameter | Why |
| --- | --- |
| `zswap.enabled=0` | Interferes with zram |
| `panic=10` | Restarts 10 s after a kernel panic, which counts as a failed start: **[➜ When the System Does Not Start](#when-the-system-does-not-start)** |
| `rd.luks.name=…=cryptroot` | Opens the disk in `sd-encrypt` |
| `rootflags=subvol=@ rootfstype=btrfs` | Which subvolume is root |
| `nowatchdog` | With Core tweaks: the watchdog is unused and delays shutdown |
| `quiet splash loglevel=3 …` | **[➜ Silent boot](https://wiki.archlinux.org/title/Silent_boot)**. `vt.global_cursor_default=0` hides the cursor on every console, so `/etc/issue.d/cursor.issue` shows it again before each login |
| `plymouth.ignore-serial-consoles` | With a serial console Plymouth falls back to text and takes the password prompt with it. Every virtual machine gets one |
| `plymouth.use-simpledrm=0` | With encryption: the splash waits for the graphics driver instead of drawing on the firmware's screen first, so the password prompt does not appear, go black and appear again. Fedora does the same behind LUKS. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Plymouth#Using_SimpleDRM)** |
| `plymouth.splash-delay=3` | With encryption: the splash shows when the password is asked, not seconds earlier as a spinner. Finding the disk takes less than 3 s. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Plymouth#Show_delay)** |

### Secure Boot

Offered only with **disk encryption**:

- Without encryption it protects nothing: the drive is readable either way
- A unified image signs kernel, initramfs and command line **as one**. Signing the kernel alone leaves the initramfs on the unencrypted partition open to changes

The chain is signed **last**. The NVIDIA driver and the boot splash rebuild the images afterwards, outside pacman and `sbctl`'s hook. From then on sbctl's mkinitcpio hook signs every unified image it builds. systemd-boot and the Recovery are recorded, so sbctl's pacman hook signs them again with every update. The Recovery's image is signed with the same keys, so it starts with Secure Boot on.

The keys are made **first**, with the boot images, before any snapshot. `/var/lib/sbctl` lives in `@`, so a snapshot from before the keys could sign nothing it rebuilds, and with Secure Boot on the next kernel update would not start. The Recovery carries the keys over a rollback for the same reason: they belong to the firmware they are enrolled in, not to a point in time.

```mermaid
flowchart LR
    B["boot loader installed"] --> D["NVIDIA driver<br/>+ boot splash"]
    D -->|rebuild the kernel image| S["Secure Boot<br/>signs, last"]

    style S fill:#1793d1,stroke:#1793d1,color:#fff
```

`sbctl verify` lists `/boot/vmlinuz-*` as not signed, and that is intended: the kernel reaches the firmware only inside the unified image. Signed on its own, it would start from any entry somebody writes onto the unencrypted EFI partition, with an initramfs and a command line of their choice.

Keys enroll only in **setup mode**. "Secure Boot disabled" is not setup mode. `-m` keeps Microsoft's certificates. A failure here is only logged, and the machine still boots.

**Note:** _systemd-boot's editor is off on every installation, signed or not. An editable command line is a root shell for anyone at the machine, past the password and past Secure Boot. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Systemd-boot#Loader_configuration)**_

#### Switching It On

After the first start, if you left it on in **Setup**:

| `sbctl status` says | Do |
| --- | --- |
| `✓` | Restart and switch Secure Boot on in the firmware |
| `✗` | Clear the Secure Boot keys in the firmware (setup mode), run `sudo sbctl enroll-keys -m`, restart and switch it on |

### The Initial Ram Disk

```
base systemd keyboard autodetect microcode modconf kms sd-vconsole block [sd-encrypt] filesystems
```

- `kms` gives Plymouth a driver to draw on. Without it there is no splash
- `keyboard` before `autodetect`: every keyboard driver ships, not only the one plugged in during the installation
- No `fsck`: the root is btrfs, whose `fsck` does nothing at boot

**Note:** _The hooks are in `/etc/mkinitcpio.conf.d/10-arch-os.conf`. Later drop-ins build on it: the boot splash (`20-`) and the NVIDIA driver (`30-`). The open drivers need none, since the `kms` hook already adds them. mkinitcpio's own pacman hook rebuilds the image whenever the NVIDIA module changes, built by DKMS or not._

## Tuning

Behind **Core tweaks**. They change behaviour, never what is installed. **[➜ Sysctl](https://wiki.archlinux.org/title/Sysctl)**

| Setting | Why |
| --- | --- |
| `vm.dirty_bytes=256M`, `_background_bytes=64M` | The default is a share of memory, which means gigabytes written in one burst. Bytes cap it at what a disk keeps up with |
| `vm.vfs_cache_pressure=50` | Directory and inode entries are cheap to keep and costly to look up again |
| `transparent_hugepage/defrag=defer+madvise` | Hands out pages at once and defragments in the background |
| `DefaultTimeoutStopSec=15s` for the session's own services | The default 90 s wait is what a hung logout looks like. System services keep systemd's default: a database, a container or a virtual machine that takes its time is still writing, and cutting it short loses data |
| `SystemMaxUse=200M` | The default keeps the journal forever on a modern disk |
| I/O scheduler | `bfq` for spinning disks, which keeps a desktop responsive while one seeks. Everything else keeps the kernel's choice: `mq-deadline` for a single queue, none for NVMe. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Improving_performance#Changing_I/O_scheduler)** |
| `strict_limit=1`, `max_ratio=10` for USB drives | A stick writes far slower than an internal disk. Without a limit a copy finishes into memory, the file manager shows little progress, and the eject waits for the rest. This holds a stick to a tenth of the limit, about 25M, from the first byte. A ratio, because the kernel keeps `max_bytes` as a ratio too. **[➜ Kernel](https://docs.kernel.org/admin-guide/abi-testing.html#abi-sys-class-bdi-bdi-strict-limit)** |
| `tcp_congestion_control=bbr`, `default_qdisc=fq` | `cubic` reads any packet loss as congestion. Wi-Fi and long-distance links lose packets without being full. `bbr` measures delay instead |

Swap is always **zram**, with or without the tweaks. **[➜ Zram](https://wiki.archlinux.org/title/Zram)**

## Accounts

One account, in `wheel`, with `sudo`. Root keeps the locked password Arch ships, so nobody logs in as root. A root password would only be a second way to the same rights. systemd's emergency shell does not open without one either, and the **[Recovery](#the-recovery)** is the way into a system that no longer starts.

- **One password** unlocks the disk and logs you in
- **Separate disk password** gives the disk its own. The login screen asks for yours, and every account has its own: the setup for a shared machine

Automatic login exists only behind disk encryption with one password. `pam_gdm` hands the passphrase typed at boot to the keyring, so the keyring must use the disk password. Only with one password is that also the account's. With **Separate disk password** the login screen asks, and the keyring uses the account password. **[➜ Arch Wiki](https://wiki.archlinux.org/title/GNOME/Keyring#PAM_step)**

### The Keyring

If the keyring's password and the login's differ, GNOME asks for the keyring's after the login. Fix it in **Passwords and Keys**, installed with `sudo pacman -S seahorse`: **Login** ➜ **Change Password**.

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

Every account starts with the same desktop: the dock, the look and the hidden applications are system defaults, see **[The Desktop](#the-desktop)**.

**Note:** _On a shared machine with one password, switch automatic login off in **Settings ➜ System ➜ Users**._

## Packages

Enough for a usable system, little enough that nothing needs looking after.

- `base`, `linux-zen`, `mkinitcpio`, `sudo`, `zram-generator`, `networkmanager`, `btrfs-progs`, `snapper`
- The processor's microcode, `intel-ucode` or `amd-ucode`, read from `/proc/cpuinfo`
- The chosen editor (`nano` unless you pick another), `man-db`, `man-pages`, `openssh`. `base` ships none of them. The editor gets a small configuration, see **[The Text Editor](#the-text-editor)**
- Everything else follows an answer: the task that enables a service installs its package

**A Wi-Fi network joined in the Installer comes along.** Each network iwd knows on the live system becomes a NetworkManager connection, so the first boot is online. A network with 802.1X has to be joined again.

**Firmware is left out in a virtual machine.** A guest's drivers are in the kernel, and `linux-firmware` is over half of the base system. A guest with a card passed through gets it.

**The graphics driver is read from the machine**, card by card, from sysfs. Nothing to choose. Mesa always, and beside it what games use: `vkd3d` for Direct3D 12 under Wine, `mesa-utils` and `vulkan-tools` to see which card a program runs on. Each vendor gets its Vulkan driver and video decoding. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Hardware_video_acceleration)**

| Card | Packages |
| --- | --- |
| Intel | `vulkan-intel`, `intel-media-driver` |
| AMD | `vulkan-radeon`, `vulkan-mesa-layers`, `opencl-mesa`. Video decoding is part of Mesa |
| NVIDIA from Turing on (device ID `0x1e00` and up) | `nvidia-open-dkms` with the kernel headers, `nvidia-utils`, `nvidia-settings`, `opencl-nvidia`, `libva-nvidia-driver`, and `nvidia-prime` beside another card |
| NVIDIA before Turing | `vulkan-nouveau`. Arch ships no NVIDIA driver for these |
| A virtual machine's own adapter | Mesa alone |

With 32-bit support each gets its `lib32-` half. NVIDIA's module loads early from the initial ram disk. The driver sets modeset and keeps video memory over a suspend by itself. **[➜ NVIDIA](https://wiki.archlinux.org/title/NVIDIA)**

**Virtual machines.** Inside one, the guest tools for its hypervisor are installed without a question. Under QEMU a desktop also gets `phodav` for the shared folders of GNOME Boxes. On a desktop, **GNOME Boxes** works as soon as you install it from GNOME Software or with `sudo pacman -S gnome-boxes`. It runs its machines as your account, through libvirt's session: no daemon, no group, no subvolume. systemd's own rule opens KVM to every account, PipeWire's JACK already serves the sound of `qemu-desktop`, and the disks live in your home, outside every snapshot, where libvirt switches copy-on-write off by itself. **[➜ GNOME Boxes](https://apps.gnome.org/Boxes/)** · **[➜ libvirt on btrfs](https://libvirt.org/formatstorage.html)**

**The browser follows the system language.** Firefox gets its language pack `firefox-i18n-<lang>`, Firefox and GNOME Web the `hunspell-<lang>` dictionary, each looked up by locale, region first, then language, and left out where Arch has none. GNOME Web also gets the GStreamer plugins WebKit plays media with, and Vivaldi gets `vivaldi-ffmpeg-codecs` for H.264 and AAC from the repositories. Nothing else is needed. Arch's Firefox follows the system language, reads the system's dictionaries and never asks to be the default. Chromium and Vivaldi carry every language and fetch their own dictionaries. Chromium runs on Wayland and decodes video on the graphics card by default since versions 140 and 143. The chosen browser opens every web link and HTML file, set with `gio mime`, and sits in the dock. **[➜ Firefox](https://wiki.archlinux.org/title/Firefox)** · **[➜ Chromium](https://wiki.archlinux.org/title/Chromium)**

**A desktop also gets `nss-mdns`**, with `mdns_minimal` in front of the resolver in `/etc/nsswitch.conf`. Avahi announces this machine and finds others either way. Without that line nothing on the system reaches them by their `.local` name, and printers, shares and other machines all answer to one. **[➜ Avahi](https://wiki.archlinux.org/title/Avahi#Hostname_resolution)**

**Note:** _File sharing announces the machine under its hostname as it is, with `mdns name = mdns` in `smb.conf`. Samba's default is the NetBIOS name, which is the hostname in capitals._

**Note:** _The public share is readable by any guest and writable only by the account Arch OS was installed with. A share any guest may write to is a folder anybody on the same network can fill._

### The Desktop

GNOME, filtered rather than installed and trimmed: what the slim desktop drops is never downloaded. GNOME Web is never taken from the group, since it is one answer to the browser question. Papers stays as a dependency of the previews in Files and is hidden from the applications.

**GNOME Software** installs Flatpaks and, with `fwupd` from the desktop extras, firmware updates. It installs no packages: Arch builds it without PackageKit, which is [not recommended](https://wiki.archlinux.org/title/Pacman/Tips_and_tricks#Graphical), so pacman stays the one tool that changes the system.

What every account starts with is a system default, not a setting copied into one home. Each account can change it.

| What | Where |
| --- | --- |
| Keyboard, dock, theme, keys, terminal font | dconf keyfiles in `/etc/dconf/db/local.d/`, read through `/etc/dconf/profile/user`. **[➜ GNOME](https://help.gnome.org/admin/system-admin-guide/stable/dconf-custom-defaults.html)** |
| Applications that come as a dependency | Hidden by an entry with `Hidden=true` in `/usr/local/share/applications/`, which comes before the packages' own |
| `~/.local/bin` on the path | `/etc/environment.d/10-arch-os.conf` |
| Git passwords in the keyring | `credential.helper` in `/etc/gitconfig` |

**Note:** _Extensions are found and installed on **[extensions.gnome.org](https://extensions.gnome.org)** through `gnome-browser-connector` from the desktop extras, and switched on and off in the **Extensions** app. **[➜ Extensions](https://wiki.archlinux.org/title/GNOME#Extensions)**_

### The Firewall

`firewalld` rather than `ufw`: NetworkManager hands it the zone of every connection, and libvirt, docker and podman open their own ports in it. There is nothing to look after: two zones carry the whole policy. `firewall-config` or any other front end can go on top. **[➜ firewalld](https://wiki.archlinux.org/title/Firewalld)**

| Zone | Where | Lets in |
| --- | --- | --- |
| `public` | Every network nobody has marked, the default zone | `dhcpv6-client`; `mdns` on a desktop; `ssh` with the SSH server |
| `home` | A network marked as trusted | What firewalld ships it with (`ssh`, `mdns`, `samba-client`, `dhcpv6-client`); `samba` and `ws-discovery-host` with file sharing |

No machine can tell a café's Wi-Fi from the one at home, so no network is trusted until you mark it. Once per network, and NetworkManager remembers it:

```
nmcli connection modify <name> connection.zone home
```

At home the router already stands between this machine and the internet, so `home` may let in what a café's Wi-Fi must not reach. The task that makes something listen opens it, in the zone it belongs in:

| Service | Opened by | Why |
| --- | --- | --- |
| `mdns` | the desktop, in `public` | Avahi's answers arrive as multicast, which no connection tracking matches to the question. Without it printers and shares stay invisible. It reveals nothing avahi does not announce anyway |
| `ssh` | the SSH server, in `public` | Logging in from another machine is what you asked for, wherever that machine is |
| `samba`, `ws-discovery-host` | file sharing, in `home` | The share itself, and `wsdd`, without which Windows does not list the machine. A share on a café's Wi-Fi is a password anybody there can try |

**Note:** _The SSH server changes nothing in `sshd_config`. Arch already refuses root a password login, and your account keeps its password because it has no key yet._

**Note:** _Flatpak adds no remote: the package ships Flathub in `/usr/share/flatpak/remotes.d/`._

### Building from the AUR

| Limit | Value | Why |
| --- | --- | --- |
| Attempts | 3 | Retries downloads, not a stuck build |
| Timeout | 45 min | Past this it is stuck, not slow |
| Compile jobs | 1 per GiB of memory, at most one per core | More would run a live system out of memory |

One `timeout` around the whole build, and passwordless `sudo` only for its length. What cargo downloads stays in the build directory and goes with it, rather than in the new home. `!debug` is added to a PKGBUILD's own `options`, never put in their place, so a package that says `!lto` keeps it.

Everything from the AUR is `allow-failure`: `paru`, the boot splash theme and the Manager. The AUR can be down for days, and nothing else needs these. A failure is counted and listed under **Test results** instead of stopping the run. Without its theme the boot splash draws Plymouth's own logo. **[➜ Oak Reference](https://github.com/murkl/oak/blob/main/docs/REFERENCE.md#tasks)**

**Note:** _With Core tweaks, `/etc/makepkg.conf.d/arch-os.conf` switches the debug package off and nothing else. An AUR build would otherwise leave a second package beside the one you wanted. `-march=native` is deliberately **not** set. It buys a few percent and costs binaries that stop running the day the disk moves to other hardware, and the crash that follows looks like failing memory._

**Note:** _Only `paru`, built from source against this machine's pacman. A `-bin` package is linked against the pacman of the day it was published and stops starting the day Arch moves `libalpm`._

### The Text Editor

The chosen editor gets a small configuration in root's home and in yours, never in `/etc`, which belongs to the package. Only what the editor ships: no plugins, no plugin manager, nothing to update but the package.

| Editor | File | Theme | Beyond its defaults |
| --- | --- | --- | --- |
| `nano` | `~/.config/nano/nanorc` | The terminal's own palette, Arch blue on the bar | Line numbers, the minibar and a scroll indicator, the mouse, auto-indent, tabs of 4, erasing what is marked, soft wrap at a word, the cursor where it was left. Highlighting from `nano-syntax-highlighting` |
| `vim` | `~/.vim/vimrc` | `habamax`, Vim's own | `defaults.vim` kept, line numbers, a status line, 4 spaces for a tab, smart-case search with matches highlighted |
| `neovim` | `~/.config/nvim/init.lua` | Neovim's own default | Line numbers, 4 spaces for a tab, smart-case search, undo that survives closing the file |
| `micro` | `~/.config/micro/settings.json` | `atom-dark` | 4 spaces for a tab, changes marked in the gutter, cursor and undo kept, folders created on save |
| `helix` | `~/.config/helix/config.toml` | `nord`, the palette of the console and the prompt | Current line and mode in colour, a bar cursor while typing, open files as tabs, indent guides, soft wrap |

**Note:** _`~/.vim/vimrc` rather than `~/.config/vim/vimrc`: Vim reads the second only where `XDG_CONFIG_HOME` is set, which a desktop leaves to the user._

## Snapshots

Snapper on every installation: a snapshot before and after every package transaction through `snap-pac`, and nothing else. No timeline and no snapshot at every boot. Between two transactions the system changes only where a snapshot should not follow, and a timeline would keep every old version of disk images, containers and databases. openSUSE leaves the timeline off for its root configuration for the same reason. One timer, `snapper-cleanup.timer`, keeps the count down.

Snapper's defaults suit a slow-moving system, not a rolling release: fifty snapshots and a year of timeline filled a disk to 70G against 35G of real system. So `NUMBER_LIMIT=10`, `NUMBER_LIMIT_IMPORTANT=5` and `TIMELINE_CREATE=no`, plus `ALLOW_GROUPS=wheel` and `SYNC_ACL=yes` so the group that owns `/.snapshots` can read it. Without them snapper answers nobody but root, whatever the directory says.

All of it lives in one place, `data/settings` beside the snapper task. `set-config` takes one `KEY=VALUE` per argument and, handed one line with all of them, writes it into the first key without a word. So the task passes them from that file, and its test reads them back against the same list.

**Note:** _`snapper-cleanup.service` syncs on `ExecStopPost`. Btrfs frees space on its own schedule, and `df` shows the wrong number until then._

### Rolling Back

**Only through the Recovery.** The kernel and its initramfs live on the EFI partition, which is not btrfs and is in no snapshot. A snapshot from before a kernel update brings back the old kernel's modules while `/boot` keeps starting the new kernel, and the machine comes up without a single module. systemd-boot has no stock way around that, so no tool for rolling back from the running desktop is installed. The Recovery puts the snapshot in place and then rebuilds the boot files from the package cache. That is also why the download cache is never emptied completely.

## Offline

An installed system needs no internet for as long as it stays offline. Only an update does, when you start one.

- Timers that go online are skipped while archlinux.org is out of reach instead of failing: the weekly mirror ranking, and the keyring's own refresh, which its package switches on. `systemctl --failed` stays empty, and the system stays `running` rather than `degraded`
- A drop-in beside each, `online.conf`, checks with `ExecCondition=`. A status from 1 to 254 is a skip and lands in the journal
- The Recovery repairs without a network, from the package cache

**Note:** _Back online after months, the packagers' keys may have changed, so update the keyring first: `sudo pacman -Sy archlinux-keyring && sudo pacman -Su`. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Pacman/Package_signing#Upgrade_system_regularly)**_

## Closing the Target

Swap off, sync, unmount, lock: in the Installer before it partitions the disk, in the Recovery before it opens it. A second attempt starts from whatever the first left behind. A restart or a shutdown leaves it to systemd, which unmounts and locks on the way down.

- `umount -R`, never `-A`. `-A` reaches beyond the target, and in the Recovery would take the rollback's snapshots with it
- `fuser -M`. Without it a target that is not a mount point resolves to the live system itself
- Whatever still holds the target is logged, then killed. The second unmount is allowed to fail for real

## When Something Goes Wrong

There are two kinds of failure, told apart by how a script stopped:

| Kind | Example | On the page |
| --- | --- | --- |
| Expected | No internet, the wrong disk, a damaged download, a USB stick pulled out | A headline and what to do, in the interface's language. Nothing to share: the words are the help |
| A script that broke | A package Arch renamed, a tool that changed its output | Module, task, script and line, the command and its output, and **Share the log** for whoever fixes the script |

A script stops itself on what it expects with `exit` and a status, and the YAML says what the status means: `3` no internet, `4` GitHub not answering, `5` the AUR not answering, under `errors:` in each `module.yaml`. Statuses from `10` up belong to the YAML beside the task or action that uses them. A failed command never counts as one of them, whatever its status. **[➜ Oak Reference](https://github.com/murkl/oak/blob/main/docs/REFERENCE.md#stopping-on-purpose)**

## Files a Task Ships

Every file a task writes into the new system lies in `data/` beside `task.sh`, named after the file it becomes. `render` from `oak.sh` puts it in place, and `where` names the folder.

```
render "$(where)/main.conf" KERNEL="$KERNEL" CMDLINE="$cmdline" >"${MNT}/boot/loader/entries/main.conf"
```

- `{{NAME}}` is the only placeholder. It is filled from `NAME=value` passed to `render`, never from the environment
- `${HOME}`, `${PATH}`, `$(date …)` and every other `$` stay as they are, for the shell, systemd or pacman that reads the file later. Nothing needs escaping
- A placeholder nobody filled, a value nothing uses and a `{{` that opens no placeholder each fail the task
- Placeholders are filled left to right and once, so a value that contains `{{` is written as it is
- A file without placeholders goes through `render` too, so a placeholder added later cannot reach a disk unfilled
- The boot entries are the exception. The Installer writes them and the Recovery lays them down again, so their templates lie in `modules/recovery/data/boot/`, which every image carries, and `boot_entries` in `oak.sh` writes them

Why not `envsubst`: it reads the environment, so every value would have to be exported under a name something else may already use. It fills an unset variable with nothing and says nothing. And without a list of names it fills every `${…}`, including those that must stay, and that list is a second copy of the template that nothing checks.

**Note:** _`make lint` refuses a `{ … } >"${MNT}/…"` block in any script._

### Where There Is No Drop-in

Where a program reads a directory, the file goes there. Four files have no such directory and are edited:

| File | Why |
| --- | --- |
| `/etc/pacman.conf` | One `Include =` line per file under `/etc/pacman.d/`, see `pacman_include`. A glob would stop pacman once it matched nothing |
| `/etc/locale.gen` | `locale-gen` reads nothing else, and a glibc update runs it again |
| `/etc/environment` | `pam_env` reads nothing else, and `sudo` takes its environment from there, so `sudo visudo` opens the chosen editor instead of a vi nobody installed |
| `/etc/nsswitch.conf` | glibc reads nothing else |

Two are written whole:

- `/etc/gdm/custom.conf`, only with automatic login, which needs disk encryption with one password. GDM reads nothing else
- `/etc/xdg/reflector/reflector.conf`. `reflector.service` names it on its command line and in its sandbox, so moving it would mean changing both

**Note:** _`/etc/hosts` stays as shipped. `filesystem` provides `localhost`, and `nss-myhostname` answers for the hostname._

## The Recovery

- From its partition: **Arch OS Recovery** in the boot menu, in the firmware's own boot menu (**F12** on most machines, not on one that lists only its boot order), or **Recovery** among the applications. It starts with Secure Boot on
- From the ISO: `recovery` on another console (**Ctrl+Alt+F2**). Switch Secure Boot off to boot the ISO and on again afterwards

It asks two questions, keyboard and disk, and on its own partition not even those. Everything else is read from the disk:

| Read | How | When |
| --- | --- | --- |
| Root partition | Partition 2, if it is a LUKS container or a btrfs labelled `BTRFS`, as the Installer makes it | Before the run |
| Encryption | The LUKS header, no password needed | Before the run |
| File system | `lsblk` on the unlocked device: btrfs, or it is refused | Once open |
| Subvolumes | `btrfs subvolume list` on the top level: every one of the layout, or it is refused | Once open |
| `/boot` | Partition 1, as the Installer lays it out, not the `fstab`, which may be what broke | While mounting |
| Kernels | `/usr/lib/modules/*/` | While rebuilding boot |
| Snapshots | `@snapshots` on the btrfs top level | Mid-run; none means the rollback is skipped |

No repair needs a network. The network may be what broke, and kernel images come from the package cache. **Configure Wi-Fi** in **Setup** joins one all the same, for an update of the Recovery or a download in the shell, on any machine with a Wi-Fi card and no internet over a cable. On its own partition a cable comes up at boot and is preferred while both are up. The Wi-Fi daemon starts once there is a card to ask. Nothing else of the network runs.

It repairs what the Installer of its release series makes: `linux-zen`, btrfs with the whole subvolume layout, systemd-boot.

You type the password of an encrypted disk once, not twice. It already exists, and it is tried on the disk as you type it (`cryptsetup open --test-passphrase`, which opens nothing), so a wrong one is refused on that page. Two boxes are for a password being chosen, which nothing can check until the system it belongs to boots.

On its own partition, the keyboard the Recovery starts with is loaded before the first page. A keyboard that will not load is asked again rather than kept, since the password is typed next.

**Note:** _A rollback builds the new `@` before it touches the old one, and the next run finishes one that was cut short in between. A run that dies halfway never leaves a system without `@`._

### The Recovery Partition

The Recovery of the release that installed the system, or a newer one of its series, on its own partition at the end of the disk, and in the boot menu as **Arch OS Recovery**. It knows this layout, and it needs neither a USB stick nor a network to start. With **Recovery** off there is none, and the ISO opens the system all the same.

It is built with the release, not on the machine, from Arch's minimal profile `baseline`: the kernel, `base`, `btrfs-progs`, `arch-install-scripts`, Plymouth, the Recovery module, and `iwd` with the firmware of the Wi-Fi cards. No editor, and nothing it starts but the Recovery and a cable's network, plus the Wi-Fi daemon once there is a card. Manuals, translations, headers, graphics drivers, and the firmware the same packages carry for graphics, cameras and Bluetooth are left out during the build.

A pre-release ISO carries it ready-made. A release's ISO leaves it out to stay under GitHub's 2 GiB limit per file, and its Installer fetches it like every other live system does: from the release the Installer belongs to, `arch-os-X.Y.Z-recovery-x86_64.tar`, checked against the checksum GitHub publishes, into `/tmp`, before the disk is touched. Either way the Installer only writes it:

| File | Goes to | What it is |
| --- | --- | --- |
| `recovery.efi` | `/boot/EFI/Linux/arch-os-recovery.efi` | Kernel, initramfs and command line as one image. systemd-boot lists it by itself under the name its `os-release` gives it. The firmware lists it as **Arch OS Recovery**, outside its boot order, because an Insyde firmware moves an entry it finds there to the front for good |
| `recovery.img` | partition 3, byte for byte | A read-only erofs holding the root file system and its signature. The running system never mounts it, only an update writes to it, and the file manager does not list it |

How it starts:

1. The boot loader starts the image. With Secure Boot it is signed with the machine's own keys, like the system's images
2. The initramfs finds the partition by the UUID its command line names. The UUID is made for each build, so no other disk is taken for it
3. It checks the root file system against a certificate it carries. The key that signed it was made for the build and thrown away afterwards, so nothing on the partition starts that the build did not make, and a damaged partition stops at a prompt that says so. The certificate is valid from 1970 to 9999, because a machine whose clock battery died still needs repairing
4. It copies the root file system to memory, so nothing of the disk stays in use while the Recovery works on it, and starts it
5. Plymouth draws on the screen the firmware set up (`nomodeset`, so no graphics driver and no firmware for one), with `plymouth.ignore-serial-consoles` like the system. The Recovery runs on tty1
6. The Recovery reads what the Installer left on the EFI partition, `EFI/arch-os-recovery/`, read-only and unmounted again at once. Its disk is the one with the partition it was started from. So it opens straight on its menu, in the language the Installer was read in and on the keyboard it was typed on

It is a kiosk: the Recovery is the only thing the machine runs, and nothing leads to a prompt. Its unit holds tty1 and never hands it back, and no other console has a login. You leave it with **Exit**, as on the ISO, and its systemd unit starts it again with every answer it had, straight back to starting (`RestartMode=direct`), so the ISO's login on tty1 never shows in between. What the Installer left is read once per boot. A crash restarts it the same way, and the first thing a run does is close whatever the last one left open. The shell inside the repaired system is a row on the page the repair ends on, behind the disk's password where there is one.

**Note:** _The EFI partition is not signed, so what the Recovery reads there goes through the same patterns and lists as any answer from a file. The worst a changed file can do is ask a question again._

**Note:** _`systemctl reboot --boot-loader-entry=arch-os-recovery.efi` starts it once from the running system. On a desktop, **Recovery** among the applications does that after one question, and logind lets whoever sits at the machine do it without a password. The question comes from the launcher itself, in English or German depending on the session's language, with **Restart** and **Cancel**, and opens on **Cancel**. Its icon is the theme's `system-reboot`, with a copy in `hicolor` for themes like Adwaita that have it only as a symbolic icon._

#### Updating It

**Update the Recovery** in **Setup**. It looks at the releases on GitHub first and says so if there is nothing to install. Otherwise it installs after a question that opens on **No**.

- Only within the release series: 2.0.0 takes 2.4.1, never 3.0.0. A new major version may lay a system out differently, and its Recovery would not repair this one. The newest release of the series counts, even after a newer major version is out
- On its own partition it offers a Recovery newer than itself. Started from the ISO, it offers one only for a disk whose Recovery no longer starts, the way back after an update was cut short
- Everything that can fail comes before the partition is touched: the download, checked against the checksum GitHub publishes, its size against the partition, and the signature. An encrypted system is opened for it, because where the system signs its boot chain, its own keys sign the new image too, whether Secure Boot is on right now or not. That is why the disk's password is asked
- Then it writes the partition, reads it back from the disk, and moves the boot image over the old one. The two disagree only while the partition is written. A machine that loses power right then starts the system as before. Its Recovery starts again once the partition is written again, from the Recovery on the ISO
- The partition keeps its partition UUID, so the file manager keeps hiding it

**Note:** _Without disk encryption, anyone at the machine can open the system from the Recovery, as from any USB stick or by taking the disk out. Encryption closes that: the Recovery asks for the password like everything else._

## The Boot Medium

A hybrid ISO already carries its partition table and boot paths, so writing it is one raw copy.

- The image is the release `version:` in `oak.yaml` names
- It lands in `~/Downloads`, or another folder set in **Setup**. An image already there is used instead of downloaded again
- The device is asked each time you choose **Start**, before the password, and never kept: a path like `/dev/sdb` names a stick only while it is plugged in
- It is checked against the checksum GitHub publishes for that release. A mismatch discards the image instead of keeping a broken one. The checksum is read once, when the image is downloaded or found, and kept beside it as `.sha256`
- If that release publishes no checksum, nothing is written. **Verify checksum** off in **Setup** writes the image in the folder as it is, without asking the release anything. That is how an image you built yourself gets onto a stick

**Root only for the write.** `as_root` wraps `umount`, `dd` and `blockdev`, nothing else. Everything else runs as you, so no root-owned file of the image lands in your home. Where `sudo` wants a password, the interface asks for it right before the run, tries it with `sudo` there, and hands it to `sudo` on stdin. The screen is never handed to a prompt, and the step shows how far `dd` has got.

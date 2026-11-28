# Reference

What Arch OS writes to a disk, and why.

## Start

The ISO is a hybrid image, so any USB writer works. It boots into the Installer on tty1. A second console (**Ctrl+Alt+F2**) logs in as root. **[➜ Arch Wiki](https://wiki.archlinux.org/title/USB_flash_installation_medium)**

| Command | Does |
| --- | --- |
| `arch-os installer` | Opens the Installer |
| `arch-os recovery` | Opens the Recovery |
| `iwctl` | Connects to Wi-Fi |

When the interface stops, tty1 returns to a root login and nothing restarts it. `journalctl -b -u arch-os` names the reason.

### Keys

Each page names its keys in the footer.

| Key | Does |
| --- | --- |
| `↑` `↓` | Choose, also `j` `k` |
| `⏎` | Open, also `l` |
| `esc` | Back, also `backspace` `h` |
| `f` | Filter |
| `tab` | Details of a run |
| `r` | Check a requirement again |
| `q` | Quit, also `ctrl+c` |

### Answers

Every answer except the passwords is saved to `installer.conf` as soon as it is given. An interrupted run resumes with them, also a second run on the ISO.

| Use | How |
| --- | --- |
| Same answers on another machine | Copy `installer.conf` from `/var/log/arch-os/` next to the Installer |
| Unattended | Run `arch-os installer --unattended` with `installer.conf` next to it and `ARCH_OS_PASSWORD` in the environment. **[➜ Runtime](../runtime/README.md#unattended)** |

### Commands

Every command that changes the system is shown and recorded in three places.

| Place | Form |
| --- | --- |
| `tab` | A box named after the step, above the command's output |
| `installer.log` | One line per command |
| `installer.sh` | A script of all commands |

`installer.sh` lies next to the Installer and in `/var/log/arch-os/` of the new system. Like the answers and the log, only root can read it. On the same machine the script installs the same system again: partitions, packages, files, accounts and services.

1. Copy `/var/log/arch-os/installer.sh` to another drive with `sudo`, since the script erases the disk it lies on
2. Boot the ISO, connect to the internet and open a shell with **Ctrl+Alt+F2**
3. Run `bash installer.sh`

The script stops outside a live system and where the disk's name points at another disk. It asks for the passwords, or reads `ARCH_OS_PASSWORD` and `ARCH_OS_DISK_PASSWORD`, and names the disk in a question that opens on **No**. A failed command stops it.

Two things differ from the original run.

| Differs | What |
| --- | --- |
| New on each run | Package versions, the ranked mirrors, the machine ID and keys such as those of Secure Boot and SSH |
| Not in the script | Wi-Fi networks, which would carry their passphrase. Checks, retries and the clean-up of an earlier attempt |

## Disk

Arch OS takes a whole disk on a UEFI machine and partitions it with GPT. It is the only system on that disk. The disk needs at least 16 GiB, or 32 GiB with GNOME. The size is checked before anything is written.

### Partitions

| Partition | Name | Size | Type | Mounted |
| --- | --- | --- | --- | --- |
| 1 | `boot` | 1 GiB | EFI system (`ef00`), FAT labeled `BOOT` | `/boot`, `fmask=0077,dmask=0077` |
| 2 | `root` | The rest | Linux x86-64 root (`8304`), btrfs labeled `BTRFS` | `/` |
| 3 | `recovery` | 1 GiB, twice the image | Linux (`8300`) | Never. **[➜ Recovery Partition](#recovery-partition)** |

- The root partition type follows the **[Installation guide](https://wiki.archlinux.org/title/Installation_guide#Example_layouts)**, so systemd's tools find the partition
- Partition 3 exists only with **Recovery**. It lies at the end of the disk, so root stays partition 2

With **Disk encryption**, partition 2 is a LUKS2 container opened as `cryptroot`. Its password is the account password or a separate one. **[➜ Accounts](#accounts)**

| LUKS2 header flag | Effect |
| --- | --- |
| `--allow-discards` | TRIM passes through, so `fstrim.timer` needs no kernel parameter. This reveals which blocks are free, not their content. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Dm-crypt/Specialties#Discard/TRIM_support_for_solid_state_drives_(SSD))** |
| `--perf-no_read_workqueue`, `--perf-no_write_workqueue` | Set on an SSD only. Requests reach the disk directly instead of waiting in a queue. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Dm-crypt/Specialties#Disable_workqueue_for_increased_solid_state_drive_(SSD)_performance)** |

**Note:** _`--persistent` stores the flags in the header, so they apply on every unlock._

### Btrfs Subvolumes

| Subvolume | Mounted | Why separate |
| --- | --- | --- |
| `@` | `/` | The system. A rollback replaces it |
| `@home` | `/home` | Personal files. A rollback leaves them untouched |
| `@snapshots` | `/.snapshots` | The snapshots |
| `@log` | `/var/log` | Logs that show why a rollback was needed |
| `@cache` | `/var/cache` | The package cache is large and not needed in a snapshot |
| `@tmp` | `/var/tmp` | Scratch space, set to `chmod 1777` before systemd-tmpfiles runs |

- A snapshot of `@` excludes nested subvolumes, so a rollback keeps all six
- A subvolume created inside `@` later, such as a container image, moves to the new `@` on a rollback
- All are mounted with `noatime,compress=zstd:1`, as on Fedora. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Btrfs#Compression)**
- The Recovery opens only a disk that has all of them

## Boot Chain

systemd-boot starts the system, its fallback and the Recovery. With **Secure Boot**, each entry starts a unified kernel image (UKI) signed with the machine's own keys.

| Part | How |
| --- | --- |
| Loader | First in the firmware boot order |
| UKIs | `/boot/EFI/arch-os/` |
| Menu | Hidden. Holding **Space** shows it, the Recovery is also in the firmware boot menu |
| Order | System, fallback, Recovery |
| Command line | `/etc/kernel/cmdline`, shared by images and entries |
| Editor | Off, since an editable command line is a root shell. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Systemd-boot#Loader_configuration)** |

**Note:** _Firmware entries of earlier systems on the disk are removed with its partitions. Entries of other disks stay._

### Fallback

Each entry gets three tries. After three failed starts the loader moves on to the next entry. This needs no key, USB stick or network. The fallback image includes every kernel module. **[➜ Automatic Boot Assessment](https://systemd.io/AUTOMATIC_BOOT_ASSESSMENT/)**

A start is good once `boot-complete.target` is reached.

| Start | Counts as |
| --- | --- |
| Disk mounted and, with GNOME, the login screen or a session up | Good |
| To the console, such as with `multi-user.target` as default | Good. It waits for no session |
| With GNOME, no session within 5 minutes | Failed. `arch-os-session-up.service` waits that long |
| Interrupted, such as a power-off at the password prompt | Failed |
| Kernel panic | Failed. `panic=10` restarts the machine, so a system that panics on every start reaches the Recovery |
| Emergency mode, in the system or its initramfs | Failed. The machine restarts after 10 s. Root has no password, so nobody could use the emergency shell |

A good start restores the tries of both entries. No entry is the default, since a default entry starts however often it failed.

### Kernel Parameters

| Parameter | Why |
| --- | --- |
| `rd.luks.name=…=cryptroot` | Opens the disk in `sd-encrypt` |
| `rootflags=subvol=@ rootfstype=btrfs` | Selects the root subvolume |
| `zswap.enabled=0` | zswap conflicts with zram |
| `panic=10` | A panic restarts the machine and counts as a failed start |
| `quiet loglevel=3 …` | **[Silent boot](https://wiki.archlinux.org/title/Silent_boot)** |
| `vt.global_cursor_default=0` | Hides the console cursor. `/etc/issue.d/cursor.issue` restores it at each login |
| `splash plymouth.ignore-serial-consoles` | Set with the boot splash. Every VM has a serial console, which would switch Plymouth to text mode, password prompt included |
| `plymouth.use-simpledrm=0` | Set with encryption. The password prompt waits for the graphics driver instead of appearing twice. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Plymouth#Using_SimpleDRM)** |
| `plymouth.splash-delay=3` | Set with encryption. Splash and password prompt appear together. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Plymouth#Show_delay)** |

### Initramfs

```
base systemd keyboard autodetect microcode modconf kms sd-vconsole block [sd-encrypt] filesystems
```

The hooks lie in `/etc/mkinitcpio.conf.d/`. `keyboard` comes before `autodetect`, so every keyboard works at the password prompt. With NVIDIA as the only card, `kms` is left out. **[➜ Arch Wiki](https://wiki.archlinux.org/title/NVIDIA#Early_loading)**

### Secure Boot

Offered only with disk encryption, since without it the disk is readable anyway. The Installer creates the machine's own keys with sbctl and signs loader, UKIs and Recovery. sbctl's hooks sign every image built later.

Keys enroll only in **setup mode**, which is not the same as "Secure Boot disabled".

| Option | Keeps |
| --- | --- |
| `-m` | Microsoft's certificates |
| `-f` | The firmware's own certificates, which firmware signed by its maker needs |

Where sbctl refuses `-f`, the Installer enrolls with `-m` alone. Keys that did not enroll are a warning on the last page. The machine still boots.

### Turning It On

After the first reboot, with **Secure Boot** among the answers:

| `sbctl status` shows | Action |
| --- | --- |
| `✓` | Restart and turn Secure Boot on in the firmware |
| `✗` | Clear the keys in the firmware, which enters setup mode. Run `sudo sbctl enroll-keys -m -f`, or with `-m` alone where that fails. Restart and turn Secure Boot on |

### Firmware Updates

fwupd's updater is signed as `fwupdx64.efi.signed`. `DisableShimForSecureBoot` lets fwupd start it without shim, which Arch does not ship. **[➜ fwupd](https://github.com/fwupd/fwupd/blob/main/plugins/uefi-capsule/README.md)**

For fwupd installed later:

```
sudo sbctl sign -s -o /usr/lib/fwupd/efi/fwupdx64.efi.signed /usr/lib/fwupd/efi/fwupdx64.efi
sudo fwupdtool modify-config uefi_capsule DisableShimForSecureBoot true
```

## System

Every machine gets the same base.

| Part | Choice | Why |
| --- | --- | --- |
| Kernel | `linux-zen` everywhere | One kernel means one set of known problems. It is tuned for responsiveness under load |
| Swap | zram | **[➜ Arch Wiki](https://wiki.archlinux.org/title/Zram)** |
| Disk health | `smartd`, with Housekeeping | A disk at risk shows on every terminal and as a critical notification in every session, not only in the journal. **[➜ Arch Wiki](https://wiki.archlinux.org/title/S.M.A.R.T.#Notifying_potential_problems)** |
| Crash records | `systemd-pstore` | Moves crash records from the firmware to `/var/lib/systemd/pstore`. **[➜ systemd-pstore](https://www.freedesktop.org/software/systemd/man/latest/systemd-pstore.service.html)** |

### Tuning

These settings change behavior and install nothing. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Sysctl)**

| Setting | Why |
| --- | --- |
| `vm.dirty_bytes=256M`, `_background_bytes=64M` | The default ratio writes gigabytes in one burst |
| `vm.vfs_cache_pressure=50` | Directory entries are cheap to keep and costly to look up again |
| `transparent_hugepage/defrag=defer+madvise` | Huge pages are available at once and defragmented in the background |
| `DefaultTimeoutStopSec=15s` for session services | With the default, a hung service delays logout by 90 s. System services keep the default, since a database stopped early loses data |
| `SystemMaxUse=200M` | Caps the journal |
| `bfq` on spinning disks | Keeps the system responsive while the disk seeks. Other disks keep the kernel default. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Improving_performance#Changing_I/O_scheduler)** |
| `strict_limit=1`, `max_ratio=10` for USB drives | A copy finishes on the drive, not in memory, so ejecting does not hang. **[➜ Kernel](https://docs.kernel.org/admin-guide/abi-testing.html#abi-sys-class-bdi-bdi-strict-limit)** |
| `tcp_congestion_control=bbr`, `default_qdisc=fq` | Wi-Fi and long links lose packets without congestion, which `cubic` misreads |
| `tcp_mtu_probing=1` | Finds the smaller packet size of PPPoE or a tunnel when a router drops the ICMP message that reports it |
| `MAKEFLAGS` with one job per core, no debug package | AUR builds use every core. `-march=native` is not set, since its binaries fail on other hardware |

### Packages

The base is enough for a usable system and small enough to need no upkeep. Everything else follows the answers: the task that enables a service installs its package.

| Package | Why |
| --- | --- |
| `base`, `linux-zen`, `mkinitcpio`, `sudo`, `zram-generator`, `networkmanager`, `btrfs-progs`, `snapper` | The system itself |
| `dosfstools` | systemd checks the EFI partition at every boot. Boot counting writes there, and FAT has no journal |
| `pacman-contrib` | `paccache.timer` keeps three versions of each installed package. pacman alone keeps every version it downloads |
| Chosen editor, `man-db`, `man-pages`, `openssh` | Not part of `base` |
| `linux-firmware`, `sof-firmware`, `wireless-regdb` | `sof-firmware` drives the sound of many laptops. All three are left out in a VM without a passed-through card, since its drivers are in the kernel |

A Wi-Fi network joined in the Installer becomes a NetworkManager connection, so the first boot is online. An 802.1X network has to be joined again.

Graphics drivers come with GNOME. Each card is detected in sysfs. Mesa, `mesa-utils` and `vulkan-tools` are always installed. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Hardware_video_acceleration)**

| Card | Packages |
| --- | --- |
| Intel | `vulkan-intel`, with `intel-media-driver` from Broadwell on and `libva-intel-driver` before |
| AMD | `vulkan-radeon`, `opencl-mesa` |
| NVIDIA from Turing on (`0x1e00`) | `nvidia-open-dkms` with headers, `nvidia-utils`, `nvidia-settings`, `opencl-nvidia`, `libva-nvidia-driver`, and `nvidia-prime` beside another card. **[➜ Arch Wiki](https://wiki.archlinux.org/title/NVIDIA)** |
| NVIDIA before Turing | `vulkan-nouveau`. Arch has no NVIDIA driver for these cards |
| VM adapter | Mesa and the guest tools of the hypervisor |

**Note:** _With 32-bit support, each driver gets its `lib32-` counterpart._

**Note:** _A step the system works without may fail without stopping the run, such as the browser, the desktop extras or the VM guest tools. The last page lists it._

### AUR Builds

`paru`, the boot splash theme and the System Manager come from the AUR. Each may fail without stopping the run, since the AUR can be down for days and nothing else depends on them. `paru` is built from source, as a `-bin` package breaks whenever Arch bumps `libalpm`.

### Text Editor

The chosen editor gets a small configuration in the account's home and in root's, never in `/etc`. It uses built-in features only, so nothing but the package needs updates.

| Editor | File | Beyond its defaults |
| --- | --- | --- |
| `nano` | `~/.config/nano/nanorc` | Line numbers, minibar, mouse, auto-indent, tabs of 4, soft wrap, `nano-syntax-highlighting` |
| `vim` | `~/.vim/vimrc` | `habamax`, `defaults.vim`, line numbers, 4 spaces, smart-case search |
| `neovim` | `~/.config/nvim/init.lua` | Line numbers, 4 spaces, smart-case search, persistent undo |
| `micro` | `~/.config/micro/settings.json` | `atom-dark`, 4 spaces, changes in the gutter, cursor and undo kept |
| `helix` | `~/.config/helix/config.toml` | `nord`, mode colors, bar cursor, tabs, indent guides, soft wrap |

## Accounts

The Installer creates one account in `wheel`, with `sudo`. Root keeps Arch's locked password. `sudo` grants the same rights, and the **[Recovery](#recovery)** opens a system that no longer starts. A name that the system or a package claims, such as `docker` or `gdm`, is refused before anything is written.

| Answers | Disk | Login |
| --- | --- | --- |
| One password | Unlocked with the account password | Automatic with GNOME. `pam_gdm` passes the disk password to the keyring, which works only if it matches the account password |
| Separate disk password | Unlocked with its own password | Login screen that lists every account. Meant for shared machines |
| No encryption | Open | Login screen |

More accounts are added in **Settings ➜ System ➜ Users ➜ Add User**. **Parental Controls** there restricts an account through Flatpak. On the console, `sudo useradd -m <name>` and `sudo passwd <name>` do the same. **[➜ Arch Wiki](https://wiki.archlinux.org/title/GNOME/Keyring#PAM_step)**

**Note:** _On a shared machine with one password, turn automatic login off in **Settings ➜ System ➜ Users**._

### Keyring

GNOME asks for the keyring password after login whenever it differs from the login password. Four changes cause that.

| After | Keyring password to set |
| --- | --- |
| Changing the disk password, with automatic login | New disk password |
| Changing the account password | New account password |
| Turning automatic login on, with a separate disk password | Disk password |
| Turning automatic login off, with two passwords | Account password |

- The keyring password is changed in **Passwords and Keys** (`sudo pacman -S seahorse`) under **Login ➜ Change Password**
- The disk password is changed with `sudo cryptsetup luksChangeKey /dev/<partition>`, on the partition `lsblk -f` lists as `crypto_LUKS`

## GNOME

Packages are filtered before the installation, so what **Slim desktop** leaves out is never downloaded.

| Part | What |
| --- | --- |
| App store | GNOME Software installs Flatpaks and, with `fwupd` from **Desktop extras**, firmware. There is no PackageKit, so only pacman changes the system. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Pacman/Tips_and_tricks#Graphical)** |
| Bazaar | Replaces GNOME Software when Flatpak is chosen. `gnome-firmware` comes with it, since Bazaar installs Flatpaks only. **[➜ Bazaar](https://apps.gnome.org/Bazaar/)** |
| Browser | Default for web links and, with **Desktop extras**, pinned to the dock. Installed in the system language. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Firefox)** |
| `.local` names | `nss-mdns` comes before the resolver in `/etc/nsswitch.conf`, so printers, shares and machines resolve by name. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Avahi#Hostname_resolution)** |
| GNOME Boxes | Works once installed: libvirt session, KVM open to every account, disks in the home folder. A QEMU guest gets `phodav` for shared folders. **[➜ GNOME Boxes](https://apps.gnome.org/Boxes/)** |
| Extensions | Installed from **[extensions.gnome.org](https://extensions.gnome.org)** through `gnome-browser-connector`, with **Desktop extras**. The **Extensions** app manages them |
| File sharing | Shares the home folder and a public folder that guests read and the owner writes. Both are announced under the hostname (`mdns name = mdns`) |
| Firmware | `fwupd-refresh.timer` keeps the catalog current wherever `fwupd` is installed, with **Desktop extras** or GNOME Firmware. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Fwupd)** |

The browser gets what its language and media support need.

| Browser | Extras |
| --- | --- |
| Firefox | `firefox-i18n-<lang>`, `hunspell-<lang>` |
| GNOME Web | `hunspell-<lang>`, codecs, GPU decoding |
| Vivaldi | Codecs |

### Out of Memory

`systemd-oomd` stops one app before GNOME freezes, when memory and swap run full or the session stalls on memory. GNOME runs each app in its own scope, so nothing else is hit. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Improving_performance#Improving_system_responsiveness_under_low-memory_conditions)**

### Defaults

Every account starts with the same defaults and can change them.

| What | Where |
| --- | --- |
| Keyboard, dock, theme, keys, terminal font | dconf keyfiles in `/etc/dconf/db/local.d/`. **[➜ GNOME](https://help.gnome.org/admin/system-admin-guide/stable/dconf-custom-defaults.html)** |
| Apps installed as a dependency | Hidden by `Hidden=true` entries in `/usr/local/share/applications/` |
| `~/.local/bin` in `PATH` | `/etc/environment.d/60-arch-os.conf` |
| Git passwords in the keyring | `credential.helper` in `/etc/gitconfig` |

## Firewall

`firewalld` filters incoming connections. NetworkManager assigns each connection its zone, and libvirt and podman open their own ports. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Firewalld)**

| Zone | Where | Allows |
| --- | --- | --- |
| `public` | Every network not marked | `dhcpv6-client`, `mdns` with GNOME, `ssh` with the SSH server |
| `home` | Networks marked as trusted | firewalld's default set. With GNOME also `32768-60999/tcp`, `rdp` and `ssdp`. With file sharing also `samba` and `ws-discovery-host` |

No machine can tell a café's Wi-Fi from a home network, so a network is trusted only once it is marked:

```
nmcli connection modify <name> connection.zone home
```

| Service | Zone | Why |
| --- | --- | --- |
| `mdns` | `public` | mDNS replies arrive as multicast, which connection tracking cannot match. They reveal nothing beyond Avahi's announcements |
| `ssh` | `public` | Reachable from any network, so it takes keys only |
| `32768-60999/tcp` | `home` | GNOME's file and media sharing listen on a random port from `ip_local_port_range` and ask for no password by default |
| `rdp`, `ssdp` | `home` | GNOME's remote desktop, and players that look for its media sharing. On a café's Wi-Fi anyone could try them |
| `samba`, `ws-discovery-host` | `home` | On a café's Wi-Fi anyone could try the account password against a share |

- Docker bypasses firewalld. With the firewall, its published ports therefore bind to `127.0.0.1`, and `-p 0.0.0.0:8080:80` publishes one to the network. **[➜ Docker](https://docs.docker.com/engine/network/packet-filtering-firewalls/)**
- The SSH server takes keys only, set in `/etc/ssh/sshd_config.d/10-arch-os.conf`. The Installer asks for the account's key and writes it to `~/.ssh/authorized_keys`. It accepts a public key or a URL such as `https://github.com/<user>.keys`

## Offline

An installed system needs no internet until the next update.

- Mirror ranking and keyring refresh are skipped while archlinux.org is unreachable, so `systemctl --failed` stays empty
- The Recovery repairs from what the system holds, without downloads

**Note:** _After months offline, update the keyring first: `sudo pacman -Sy archlinux-keyring && sudo pacman -Su`. **[➜ Arch Wiki](https://wiki.archlinux.org/title/Pacman/Package_signing#Upgrade_system_regularly)**_

## Snapshots

Snapper takes snapshots of `@` on two occasions and at no other time.

| Snapshot | When | Kept |
| --- | --- | --- |
| `pre` and `post` | Before and after every package transaction, through `snap-pac` | The newest 10 |
| `last good boot` | After every **[good start](#fallback)**, through `arch-os-boot-snapshot.service` | One. The next good start replaces it |

- The boot snapshot also holds changes made by hand, such as an edited file in `/etc`, and shows a system that started
- It has no cleanup algorithm, so the limit of the package snapshots leaves it alone

| Setting | Value |
| --- | --- |
| Timeline | Off, since it keeps every version of disk images and databases |
| `NUMBER_LIMIT` | 10 |
| `ALLOW_GROUPS` | None, so `sudo snapper list` lists them |
| Cleanup | `snapper-cleanup.timer` |

### Rollback

A rollback runs from the Recovery only. The boot images lie on the EFI partition and belong to no snapshot, so an older snapshot alone would start a kernel without its modules.

1. The Recovery puts the snapshot in place of `@`
2. It rebuilds the boot files from the kernel image that Arch keeps beside the modules in `/usr/lib/modules/`, which is part of the snapshot

## Recovery

The Recovery repairs a system that no longer starts. It runs from its own partition or from the ISO.

| From | How |
| --- | --- |
| Partition | **Arch OS Recovery** in the boot menu, in the firmware boot menu (**F12** on most machines), or **Recovery** in the app grid. Works with Secure Boot on |
| ISO | `arch-os recovery` on another console (**Ctrl+Alt+F2**), with Secure Boot off |

From the ISO it asks for keyboard and disk. On its partition it asks for neither. Everything else is read from the disk, passwords are asked right before they are needed and never saved.

- Before it writes to the EFI partition, it checks it with `fsck.fat`, as the system does at boot
- It repairs what the Installer of its release series creates, and needs no network for that. **Connect to Wi-Fi** on the dashboard is there for an update or for a download in the shell
- A rollback builds the new `@` before it touches the old one and keeps the old one as a snapshot, so it can be undone. The next run completes an interrupted rollback
- `systemctl reboot --boot-loader-entry=arch-os-recovery.efi` starts it once. **Recovery** in the app grid does the same after a confirmation that opens on **Cancel**

**Note:** _Without disk encryption, anyone at the machine can open the system from the Recovery, as from any USB stick._

### Recovery Partition

The partition holds the Recovery of the release that installed the system. The ISO carries it, and the Installer writes it to the disk. It is built from Arch's `baseline` profile: kernel, `base`, `btrfs-progs`, `arch-install-scripts`, Plymouth, the Recovery, and `iwd` with Wi-Fi firmware.

| File | Target | Content |
| --- | --- | --- |
| `recovery.efi` | `/boot/EFI/Linux/arch-os-recovery.efi` | The UKI. Its firmware entry stays outside the boot order, since Insyde firmware moves any entry there to the front for good |
| `recovery.img` | Partition 3, byte for byte | A read-only erofs with its signature. The system never mounts it, and the file manager does not show it |

Its root is verified against a key deleted after the build and copied to memory, which frees the disk. It opens in the Installer's language and keyboard and runs as a kiosk: no console has a login, and **Start over** or a crash restarts it with every answer kept.

**Note:** _The EFI partition is unsigned, so what the Recovery reads there is checked like any answer from a file._

### Update

**Update the Recovery** on the dashboard checks the GitHub releases and installs after a confirmation that opens on **No**.

| Rule | Detail |
| --- | --- |
| Within its series only | 2.1.0 updates to 2.4.1, never to 3.0.0 |
| From the ISO too | The ISO updates a Recovery that is older or no longer starts |
| Safe against a power cut | The system starts as before |

**Note:** _A 2.0 Recovery with Secure Boot and disk encryption updates itself only with 4 GiB of memory. With less, the ISO updates it._

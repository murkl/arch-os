# Shared ground for every script of this tree: the system being repaired, the
# disk it is on, and the few things every task does.
#
# The runtime sources this before every task and every hook, so a script is plain
# shell with no preamble — the ERR trap that stops at the first failure is the
# runtime's. Nothing here prints for a person to read; stdout goes to the log.
#
# Nothing here asks anything either: the keyboard, the disk, the password and the
# snapshot are questions in recovery.yaml, and this file is handed the answers.
#
# What stands until the first divider is the installer's too, word for word (see
# ../installer/lib.sh). It is written out in both rather than shared from a third
# place: each tree is a program of its own, and a file neither of them owns would
# tie the two back together.

# Where the system being repaired is mounted.
MNT=/mnt

# DEBUG=true runs the recovery without touching the machine. Each task guards
# itself with `simulating && return 0` as its first line, so a unit is only ever
# skipped as a whole.
: "${DEBUG:=false}"

simulating() {
    [ "$DEBUG" = "true" ] || return 1
    echo "simulated: ${BASH_SOURCE[1]}"
    sleep 1 # so the unit is visible in the interface rather than flashing past
}

# The disks this machine has: the device path is the answer, what follows the tab
# is what it is chosen by. Nobody picks between /dev/sda and /dev/sdb by name.
# Whole disks only — 8 is SCSI and SATA, 259 NVMe, 254 virtual block devices.
disk_options() {
    lsblk -d -n -I 8,259,254 -o PATH,SIZE,MODEL |
        awk '{ path = $1; $1 = ""; sub(/^ +/, ""); sub(/ +$/, ""); printf "%s\t%s  %s\n", path, path, $0 }'
}

# part_of names a partition of a disk. Devices whose name ends in a digit —
# nvme0n1, mmcblk0, loop0 — put a p between the disk and the number.
part_of() {
    local sep=""
    [[ "$1" =~ [0-9]$ ]] && sep="p"
    printf '%s%s%s' "$1" "$sep" "$2"
}

# How this project mounts btrfs. The installer lays the file system out with
# these and this puts it back the same way, so the two must not drift apart.
BTRFS_OPTS="defaults,noatime,compress=zstd"

# ─── The keyboard this is typed on ───────────────────────────────────────────

# The keyboard the live image was started with, which the question opens on. The
# Arch image records it in root's shell history as the loadkeys command that set
# it, which is the only place it can be read back from.
live_keymap() {
    grep -h 'loadkeys' /root/.bash_history /root/.zsh_history 2>/dev/null |
        tail -n1 | sed 's/.*loadkeys *//' | tr -d ' ' || true
}

# Loaded the moment it is answered, which is the whole reason it is the first
# question: a passphrase typed on the wrong layout is not the passphrase.
load_console_keyboard() {
    # DEBUG runs on somebody's own machine, whose keyboard is not ours to touch.
    [ "$DEBUG" = "true" ] && return 0
    loadkeys "$ARCH_OS_RECOVERY_KEYMAP"
}

# ─── The system on the disk ──────────────────────────────────────────────────

# A btrfs installation is two views of one disk: the system as it runs, mounted
# at MNT, and the top level holding @ and the snapshots, where a rollback
# happens. The second is kept out of the first on purpose — it must not be inside
# a chroot, and it must survive MNT being unmounted.
BTRFS_TOP=/run/arch-os-recovery

# What the unlocked disk is called under /dev/mapper.
CRYPT=recovery

# Arch OS puts the EFI system partition first and the root second, whatever the
# disk is called.

boot_part() { part_of "$ARCH_OS_RECOVERY_DISK" 1; }
root_part() { part_of "$ARCH_OS_RECOVERY_DISK" 2; }

# What holds the file system: the unlocked mapper where the disk is encrypted,
# the root partition itself where it is not.
root_device() {
    if [ "$ARCH_OS_RECOVERY_ENCRYPTION_ENABLED" = "true" ]; then
        printf '/dev/mapper/%s' "$CRYPT"
    else
        root_part
    fi
}

# ─── What can be read off the disk before it is open ─────────────────────────
#
# Both fill in the answer their question opens on; neither is the answer. Behind
# LUKS nothing can be seen until the password has been given, and a disk laid out
# some other way has to stay answerable by hand.

fstype() { lsblk -no FSTYPE "$1" 2>/dev/null | head -n1; }

# Whether the disk is encrypted. A LUKS header is readable without the password,
# so this one is reliable.
disk_encrypted() {
    [ "$(fstype "$(root_part)")" = "crypto_LUKS" ] && echo true || echo false
}

# Readable everywhere except behind LUKS, where the question is a real one.
disk_filesystem() {
    case "$(fstype "$(root_part)")" in
    btrfs) echo btrfs ;;
    ext4) echo ext4 ;;
    esac
}

# ─── Opening it ──────────────────────────────────────────────────────────────

# Everything this recovery had mounted, taken back down, and the disk locked
# again. Run before mounting as well as after, because a second attempt starts
# from a target the first may have left half open. Nothing mounted is ordinary.
unmount_system() {
    swapoff -a || true
    sync
    if mountpoint -q "$MNT" && ! umount -A -R "$MNT"; then
        free_target
        umount -A -R "$MNT"
    fi
    mountpoint -q "$BTRFS_TOP" && umount -R "$BTRFS_TOP"
    [ -e "/dev/mapper/${CRYPT}" ] && cryptsetup close "$CRYPT"
    echo "closed ${MNT}"
}

# The installed system, mounted as it mounts itself. Separate from open_system
# because a rollback takes it apart to replace @ and then puts it back.
mount_system() {
    local target
    target="$(root_device)"
    if [ "$ARCH_OS_RECOVERY_FILESYSTEM" = "btrfs" ]; then
        mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=@" "$target" "$MNT"
        mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=@home" "$target" "${MNT}/home"
        mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=@snapshots" "$target" "${MNT}/.snapshots"
    else
        mount --mkdir "$target" "$MNT"
    fi
    mount --mkdir "$(boot_part)" "${MNT}/boot"
}

# Unlock the disk where it is encrypted and mount what is on it. The password
# goes in on stdin and never reaches a command line, which /proc would show.
open_system() {
    simulating && return 0
    unmount_system

    local root
    root="$(root_part)"
    if [ ! -b "$root" ]; then
        echo "There is no partition at ${root}. That disk does not hold an Arch OS installation." >&2
        return 1
    fi

    if [ "$ARCH_OS_RECOVERY_ENCRYPTION_ENABLED" = "true" ]; then
        if ! printf '%s' "$ARCH_OS_RECOVERY_PASSWORD" | cryptsetup open "$root" "$CRYPT"; then
            echo "The password did not unlock ${root}." >&2
            return 1
        fi
    fi

    # What is actually on it, now that it can be seen — so a wrong answer is
    # caught here rather than by a mount command that names no question.
    local found
    found="$(fstype "$(root_device)")"
    if [ "$found" != "$ARCH_OS_RECOVERY_FILESYSTEM" ]; then
        echo "That disk holds ${found:-nothing recognisable}, not ${ARCH_OS_RECOVERY_FILESYSTEM}." >&2
        return 1
    fi

    # The top level first, where a rollback does its work, and only then the
    # system as it runs.
    if [ "$ARCH_OS_RECOVERY_FILESYSTEM" = "btrfs" ]; then
        mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvolid=5" "$(root_device)" "$BTRFS_TOP"
    fi
    mount_system
    echo "opened ${ARCH_OS_RECOVERY_DISK} at ${MNT}"
}

# ─── Going back to a snapshot ────────────────────────────────────────────────

# The snapshots to go back to, newest first, as the paths a rollback reaches them
# by. A number alone is not something anyone can pick between, so the date and
# the reason are read out of each snapshot's own info.xml.
snapshots() {
    if [ "$DEBUG" = "true" ]; then
        printf '@snapshots/2/snapshot\t2   2026-08-30 21:04   after a system update\n'
        printf '@snapshots/1/snapshot\t1   2026-08-29 09:12   first root filesystem\n'
        return 0
    fi
    local path number
    while read -r path; do
        number="$(printf '%s' "$path" | cut -d/ -f2)"
        printf '%s\t%s\n' "$path" "$(snapshot_label "$number")"
    done < <(snapshot_paths)
}

# Newest first is by the number snapper counts up with, not by the order btrfs
# happens to list them in.
snapshot_paths() {
    btrfs subvolume list -o "${BTRFS_TOP}/@snapshots" |
        awk '{ print $NF }' | sort -t/ -k2 -rn
}

# One snapshot as it reads in a list. Unreadable info leaves the number standing
# on its own: a snapshot that cannot describe itself is still one to go back to.
snapshot_label() {
    local info="${BTRFS_TOP}/@snapshots/${1}/info.xml"
    local field
    printf '%s' "$1"
    for field in date description; do
        # A line at a time, so a broken file costs a column rather than the
        # whole list.
        sed -n "s:.*<${field}>\(.*\)</${field}>.*:\1:p" "$info" 2>/dev/null |
            head -n1 | sed 's/^/   /' | tr -d '\n'
    done
    echo
}

# Put the chosen snapshot in place of the root subvolume. The new @ is built
# before the old one is touched, so a rollback that dies halfway leaves the
# system as it found it rather than with no root at all.
rollback() {
    simulating && return 0
    local top="$BTRFS_TOP"
    local snapshot="$ARCH_OS_RECOVERY_SNAPSHOT"

    if [ ! -d "${top}/${snapshot}" ]; then
        echo "There is no snapshot at ${snapshot}." >&2
        return 1
    fi

    # @ cannot be replaced while it is the root that is mounted.
    umount -A -R "$MNT"

    btrfs subvolume delete --recursive "${top}/@.new" 2>/dev/null || true
    btrfs subvolume snapshot "${top}/${snapshot}" "${top}/@.new"
    btrfs subvolume delete --recursive "${top}/@"
    mv "${top}/@.new" "${top}/@"

    mount_system

    # A lock left behind by the transaction that broke this system would stop
    # the recovered one from being repaired further.
    rm -f "${MNT}/var/lib/pacman/db.lck"
    echo "@ is now ${snapshot}"
}

# ─── Making it bootable again ────────────────────────────────────────────────

# For a rollback that went back past a kernel update: the modules under the
# restored root and the image in /boot are then two different kernels.
#
# The image comes out of the package in this system's own pacman cache rather
# than off the network, which a machine being recovered may not have.
rebuild_boot() {
    simulating && return 0
    local dir version kind package
    for dir in "${MNT}/usr/lib/modules/"*/; do
        # A leftover folder with no modules in it is not a kernel.
        [ -e "${dir}kernel" ] || continue
        version="$(basename "$dir")"
        kind="$(kernel_package "$version")"
        package="$(kernel_cached "$kind" "$version")"
        if [ -z "$package" ]; then
            echo "There is no ${kind} package for ${version} in the package cache." >&2
            return 1
        fi
        bsdtar -xOf "$package" "usr/lib/modules/${version}/vmlinuz" >"${MNT}/boot/vmlinuz-${kind}"
        echo "restored vmlinuz-${kind} from $(basename "$package")"
    done

    # The presets are the one place that knows whether this system boots a
    # plain ram disk or a signed unified image.
    arch-chroot "$MNT" mkinitcpio -P

    # GRUB lists the snapshots it can boot from the file system, so its menu is
    # stale the moment @ changes. systemd-boot has nothing to regenerate.
    [ -f "${MNT}/boot/grub/grub.cfg" ] && arch-chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg
    echo "boot rebuilt"
}

# Which package a module directory belongs to: 6.12.4-arch1-1 is the stock
# kernel, anything carrying zen, lts or hardened is that one.
kernel_package() {
    case "$1" in
    *zen*) echo linux-zen ;;
    *lts*) echo linux-lts ;;
    *hardened*) echo linux-hardened ;;
    *) echo linux ;;
    esac
}

# The newest cached package for a kernel, or nothing. A module directory is named
# after the package version with the release joined on, so what stands before the
# first hyphen is what the file name carries.
kernel_cached() {
    { find "${MNT}/var/cache/pacman/pkg" -maxdepth 1 -name "${1}-${2%%-*}*.pkg.tar.*" 2>/dev/null || true; } |
        sort -V | tail -n1
}

# ─── Leaving ─────────────────────────────────────────────────────────────────

# Whatever still has the system open, named in the log and then killed — a
# process a chroot left running. The pause is what the kernel needs to let go of
# its files afterwards.
#
# -M is the whole safety of it: without it a target that is not a mount point
# resolves to the file system containing it, which on the live image is the live
# image itself.
free_target() {
    echo "the target did not unmount, what is holding it:"
    fuser -Mvm "$MNT" || true
    fuser -Mkm "$MNT" || true
    sleep 2
}

# What the restart and shutdown hooks do. Whatever is open is closed first, so a
# machine restarted halfway through does not take a half-written file system with
# it. Nothing mounted is not an error.
leave_machine() {
    simulating && return 0
    unmount_system || true
    systemctl "$1"
}

# The recovery: opening an Arch OS installation that is already on a disk, and
# putting its root subvolume back the way it was.
#
# Sourced by lib.sh, so it is in scope for every task, hook and option list of
# this tree the same way the rest of it is. The split is what it is called:
# lib.sh is what an installation shares, this is what a recovery shares, and
# neither reads the other's variables.
#
# Nothing here asks anything. The disk, the password and the snapshot are
# questions in installer.yaml, asked in the interface like every other — this
# file only ever gets handed the answers.

# Where an installed system is mounted while it is worked on. The installer's
# own target, so both halves of this tree take a mount down the same way and
# `free_target` means one thing.
#
# A btrfs installation is two views of one disk: the system as it runs, mounted
# at MNT, and the top level holding @ and the snapshots beside it, which is
# where a rollback happens. The second is kept out of the first deliberately —
# it must not be inside a chroot, and it must survive MNT being unmounted.
RECOVERY_TOP=/run/arch-os-recovery
RECOVERY_CRYPT=recovery

# ─── The disk, as it was laid out ────────────────────────────────────────────
#
# Arch OS installs the EFI system partition first and the root second. That is
# what an installation of it looks like whatever the disk is called, and
# `part_of` is what turns a disk and a number into the name the kernel gives it.

recovery_boot_part() { part_of "$ARCH_OS_RECOVERY_DISK" 1; }
recovery_root_part() { part_of "$ARCH_OS_RECOVERY_DISK" 2; }

# What holds the file system: the unlocked mapper where the disk is encrypted,
# the root partition itself where it is not.
recovery_target() {
    if [ "$ARCH_OS_RECOVERY_ENCRYPTION_ENABLED" = "true" ]; then
        printf '/dev/mapper/%s' "$RECOVERY_CRYPT"
    else
        recovery_root_part
    fi
}

# ─── What can be read off the disk before it is open ─────────────────────────
#
# Both of these fill in the answer their question opens on. Neither is the
# answer: behind LUKS nothing can be seen until the password has been given, and
# a disk that is not laid out the way Arch OS lays one out has to stay
# answerable by hand.

recovery_fstype() { lsblk -no FSTYPE "$1" 2>/dev/null | head -n1; }

# Whether the disk is encrypted. A LUKS header is readable without the password,
# so this one is reliable.
recovery_is_encrypted() {
    [ "$(recovery_fstype "$(recovery_root_part)")" = "crypto_LUKS" ] && echo true || echo false
}

# The file system of the installed system, where it can be read at all — which
# is everywhere except behind LUKS. Nothing there, and the question is a real
# one.
recovery_filesystem() {
    case "$(recovery_fstype "$(recovery_root_part)")" in
    btrfs) echo btrfs ;;
    ext4) echo ext4 ;;
    esac
}

# ─── Opening it ──────────────────────────────────────────────────────────────

# Everything this recovery had mounted, taken back down, and the disk locked
# again. Run before mounting as well as after: a second attempt in the same
# session starts from a target somebody may have left half open.
#
# Nothing mounted is the ordinary case rather than a failure — the question is
# as likely to be asked before the first task as after the last.
recovery_unmount() {
    swapoff -a || true
    sync
    if mountpoint -q "$MNT" && ! umount -A -R "$MNT"; then
        free_target
        umount -A -R "$MNT"
    fi
    mountpoint -q "$RECOVERY_TOP" && umount -R "$RECOVERY_TOP"
    [ -e "/dev/mapper/${RECOVERY_CRYPT}" ] && cryptsetup close "$RECOVERY_CRYPT"
    echo "closed ${MNT}"
}

# The installed system, mounted as it mounts itself: @ where the root goes, home
# and the snapshots under it, and the EFI partition on /boot.
#
# Separate from recovery_open because a rollback has to take this apart to
# replace @ and then put it back exactly as it was.
recovery_mount_system() {
    local target
    target="$(recovery_target)"
    if [ "$ARCH_OS_RECOVERY_FILESYSTEM" = "btrfs" ]; then
        mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=@" "$target" "$MNT"
        mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=@home" "$target" "${MNT}/home"
        mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=@snapshots" "$target" "${MNT}/.snapshots"
    else
        mount --mkdir "$target" "$MNT"
    fi
    mount --mkdir "$(recovery_boot_part)" "${MNT}/boot"
}

# Unlock the disk where it is encrypted and mount what is on it.
#
# The password goes in on stdin and never reaches a command line: an installer
# is watched, and /proc is readable by anyone sitting at this machine.
recovery_open() {
    simulating && return 0
    recovery_unmount

    local root
    root="$(recovery_root_part)"
    if [ ! -b "$root" ]; then
        echo "There is no partition at ${root}. That disk does not hold an Arch OS installation." >&2
        return 1
    fi

    if [ "$ARCH_OS_RECOVERY_ENCRYPTION_ENABLED" = "true" ]; then
        if ! printf '%s' "$ARCH_OS_RECOVERY_PASSWORD" | cryptsetup open "$root" "$RECOVERY_CRYPT"; then
            echo "The password did not unlock ${root}." >&2
            return 1
        fi
    fi

    # What is actually on it, now that it can be seen. An answer that turns out
    # to be wrong is caught here rather than by a mount command whose complaint
    # says nothing about which question was answered badly.
    local found
    found="$(recovery_fstype "$(recovery_target)")"
    if [ "$found" != "$ARCH_OS_RECOVERY_FILESYSTEM" ]; then
        echo "That disk holds ${found:-nothing recognisable}, not ${ARCH_OS_RECOVERY_FILESYSTEM}." >&2
        return 1
    fi

    # The top level first, where a rollback does its work, and only then the
    # system as it runs.
    if [ "$ARCH_OS_RECOVERY_FILESYSTEM" = "btrfs" ]; then
        mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvolid=5" "$(recovery_target)" "$RECOVERY_TOP"
    fi
    recovery_mount_system
    echo "opened ${ARCH_OS_RECOVERY_DISK} at ${MNT}"
}

# ─── Going back to a snapshot ────────────────────────────────────────────────

# The snapshots there are to go back to, newest first, as the paths a rollback
# reaches them by. What follows the tab is what they are chosen by: a number
# alone is not something anyone can pick between, so the date snapper wrote and
# the reason it gives are read out of the snapshot's own info.xml.
recovery_snapshots() {
    if [ "$DEBUG" = "true" ]; then
        printf '@snapshots/2/snapshot\t2   2026-08-30 21:04   after a system update\n'
        printf '@snapshots/1/snapshot\t1   2026-08-29 09:12   first root filesystem\n'
        return 0
    fi
    local path number
    while read -r path; do
        number="$(printf '%s' "$path" | cut -d/ -f2)"
        printf '%s\t%s\n' "$path" "$(recovery_snapshot_label "$number")"
    done < <(recovery_snapshot_paths)
}

# Every snapshot subvolume under @snapshots, newest first — which is by the
# number snapper counts up with, not by the order btrfs happens to list them in.
recovery_snapshot_paths() {
    btrfs subvolume list -o "${RECOVERY_TOP}/@snapshots" |
        awk '{ print $NF }' | sort -t/ -k2 -rn
}

# One snapshot as it reads in a list: its number, when it was taken and what
# took it. Missing or unreadable info leaves the number standing on its own,
# because a snapshot that cannot describe itself is still one to go back to.
recovery_snapshot_label() {
    local info="${RECOVERY_TOP}/@snapshots/${1}/info.xml"
    local field
    printf '%s' "$1"
    for field in date description; do
        # One line of XML at a time, so a file that is not what it should be
        # costs a column rather than the whole list.
        sed -n "s:.*<${field}>\(.*\)</${field}>.*:\1:p" "$info" 2>/dev/null |
            head -n1 | sed 's/^/   /' | tr -d '\n'
    done
    echo
}

# Put the chosen snapshot in place of the root subvolume.
#
# The new @ is built before the old one is touched and swapped in only once it
# is there, so a rollback that dies halfway leaves the system exactly as it
# found it rather than with no root at all. The old @ goes after that, and not
# before: it is the only copy of the state being left behind.
recovery_rollback() {
    simulating && return 0
    local top="$RECOVERY_TOP"
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

    recovery_mount_system

    # A lock left behind by the package transaction that broke this system, and
    # the one thing that would stop the recovered one from being repaired
    # further.
    rm -f "${MNT}/var/lib/pacman/db.lck"
    echo "@ is now ${snapshot}"
}

# ─── Making it bootable again ────────────────────────────────────────────────

# Rebuild what boots the system, for a rollback that went back past a kernel
# update: the modules under the restored root and the image in /boot are then
# two different kernels, and the machine comes up without a single one of them.
#
# The image is taken out of the package in this system's own pacman cache rather
# than downloaded. A machine being recovered is not reliably on a network, and
# the package that put those modules there is the one that has the matching
# image in it.
recovery_rebuild_boot() {
    simulating && return 0
    local dir version kind package
    for dir in "${MNT}/usr/lib/modules/"*/; do
        # A leftover folder with no modules in it is not a kernel.
        [ -e "${dir}kernel" ] || continue
        version="$(basename "$dir")"
        kind="$(recovery_kernel_package "$version")"
        package="$(recovery_kernel_cached "$kind" "$version")"
        if [ -z "$package" ]; then
            echo "There is no ${kind} package for ${version} in the package cache." >&2
            return 1
        fi
        bsdtar -xOf "$package" "usr/lib/modules/${version}/vmlinuz" >"${MNT}/boot/vmlinuz-${kind}"
        echo "restored vmlinuz-${kind} from $(basename "$package")"
    done

    # Every initial ram disk this system's own presets describe — which is the
    # one place that knows whether it boots a plain image or a signed unified
    # one.
    arch-chroot "$MNT" mkinitcpio -P

    # GRUB lists the snapshots it can boot from the file system, so its menu is
    # stale the moment @ changes. systemd-boot has nothing to regenerate.
    [ -f "${MNT}/boot/grub/grub.cfg" ] && arch-chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg
    echo "boot rebuilt"
}

# Which package a module directory belongs to. The suffix is the whole of what
# says so: 6.12.4-arch1-1 is the stock kernel, anything carrying zen, lts or
# hardened is that one.
recovery_kernel_package() {
    case "$1" in
    *zen*) echo linux-zen ;;
    *lts*) echo linux-lts ;;
    *hardened*) echo linux-hardened ;;
    *) echo linux ;;
    esac
}

# The newest cached package for a kernel, or nothing at all. A module directory
# is named after the package version with the release joined on, so what stands
# in front of the first hyphen is what the file name carries.
recovery_kernel_cached() {
    { find "${MNT}/var/cache/pacman/pkg" -maxdepth 1 -name "${1}-${2%%-*}*.pkg.tar.*" 2>/dev/null || true; } |
        sort -V | tail -n1
}

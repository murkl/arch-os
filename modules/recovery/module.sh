# What more than one script of this module has to agree about, sourced by Oak in
# front of every one of them. Anything a single script needs stays in that
# script; the functions a declaration calls by name are at the bottom.

# Where the system being repaired is mounted, and what the unlocked disk is
# called under /dev/mapper.
MNT=/mnt
CRYPT=recovery

# An installation is two views of one disk: the system as it runs, mounted at
# MNT, and the btrfs top level holding @ and the snapshots, where a rollback
# happens. Kept out of MNT on purpose - it must not end up inside a chroot, and
# it must survive MNT being unmounted.
BTRFS_TOP=/run/arch-os-recovery

# ////////////////////////////////////////////////////////////////////////////
# WHAT THE DISK IS
# ////////////////////////////////////////////////////////////////////////////

# The partition the installation is on: the second, where the Installer puts
# it. Taken for it only while it holds what the Installer makes of it - a LUKS
# container, or a btrfs labelled BTRFS - so a disk that is something else is
# turned away before anything on it is opened. /boot is read out of the
# installation's own fstab once it is open - see mount_target.
#
# Raw output with a single space between columns, so a column left empty stays
# a column.
root_partition() {
    local part
    part="$(part_of "$ARCH_OS_RECOVERY_DISK" 2)"
    lsblk -dnro FSTYPE,LABEL "$part" 2>/dev/null | awk -F'[ ]' -v part="$part" '
        $1 == "crypto_LUKS" || ($1 == "btrfs" && $2 == "BTRFS") { print part }'
}
ROOT_PART="$(root_partition)"

# What holds the file system: the unlocked mapper device where the disk is
# encrypted, the root partition itself where it is not.
root_device() {
    if [ "$ARCH_OS_RECOVERY_ENCRYPTED" = "true" ]; then
        printf '/dev/mapper/%s' "$CRYPT"
    else
        printf '%s' "$ROOT_PART"
    fi
}

# What a block device itself holds, or nothing for one that holds nothing
# readable.
#
# --nodeps is what makes it the device's own answer. Without it lsblk also
# prints what is layered on top and puts the child first, so an unlocked LUKS
# partition answers `btrfs` - and the question below, which the runtime asks
# again every time an answer changes, then says the disk is not encrypted from
# the moment it has been opened. The rollback asks for the snapshot mid-run,
# which is such a change, and everything after it went looking for the file
# system on the locked partition instead of on the mapper.
fstype() { lsblk -dno FSTYPE "$1" 2>/dev/null || true; }

# Every subvolume of the layout the top level lacks, one per line, and nothing
# where it has them all - the answer to whether this is an installation this
# release of the Recovery knows how to open.
missing_subvolumes() {
    local present subvolume
    present="$(btrfs subvolume list "$BTRFS_TOP" | awk '{ print $NF }')"
    while read -r subvolume _; do
        grep -qxF "$subvolume" <<<"$present" || echo "$subvolume"
    done < <(btrfs_subvolumes)
}

# ////////////////////////////////////////////////////////////////////////////
# THE KERNELS ON THE DISK
# ////////////////////////////////////////////////////////////////////////////

# Every kernel whose modules are in the system being repaired. A folder with no
# modules under it is what an interrupted removal leaves, not a kernel.
installed_kernels() {
    local dir
    for dir in "${MNT}/usr/lib/modules/"*/; do
        [ -e "${dir}kernel" ] || continue
        basename "$dir"
    done
}

# ////////////////////////////////////////////////////////////////////////////
# MOUNTING & CLOSING
# ////////////////////////////////////////////////////////////////////////////

# The installed system, mounted exactly as it mounts itself. Shared because a
# rollback takes it apart to replace @ and has to put it back as open left it.
mount_target() {
    local subvolume path

    # @ first, since every other mount point is a directory inside it.
    while IFS=$'\t' read -r subvolume path; do
        mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=${subvolume}" "$(root_device)" "${MNT}${path%/}"
    done < <(btrfs_subvolumes)

    # As the system mounts it itself, with the options its own table gives it.
    mount --fstab "${MNT}/etc/fstab" --target-prefix "$MNT" --mkdir /boot
}

# Everything under /mnt, taken back down. Nothing mounted is not an error: a
# rollback takes the system apart with this in the middle of a run. Whatever
# still holds it is named in the log and then killed, and the second attempt is
# left unguarded on purpose - that one is a real failure.
#
# -R and not -A: -A reads the target as every mount point of this file system
# wherever it is, and the top level is a second mount of the same disk. -M
# carries the whole safety of the two fuser lines - without it a target that is
# not itself a mount point resolves to the live image.
unmount_target() {
    mountpoint -q "$MNT" || return 0
    umount -R "$MNT" && return 0

    echo "the target did not unmount, what is holding it:"
    fuser -Mvm "$MNT" || true
    fuser -Mkm "$MNT" || true
    sleep 2 # the kernel needs a moment to actually let go of the files

    umount -R "$MNT"
}

# The system closed for good. Run before opening as well as after, because a
# second attempt starts from a target the first may have left half open.
close_target() {
    swapoff -a || true
    sync
    unmount_target || return 1 # a system still standing cannot be locked either
    mountpoint -q "$BTRFS_TOP" && umount -R "$BTRFS_TOP"
    [ -e "/dev/mapper/${CRYPT}" ] && cryptsetup close "$CRYPT"
    echo "closed ${MNT}"
}

# ////////////////////////////////////////////////////////////////////////////
# THE YAML | Every function a declaration calls by name
# ////////////////////////////////////////////////////////////////////////////

list_keymaps() { localectl list-keymaps; }

# Loaded the moment it is answered. A simulated run is on somebody's own
# machine, whose keyboard is not ours to touch.
load_console_keyboard() {
    debugging && return 0
    loadkeys "$ARCH_OS_RECOVERY_KEYMAP"
}

# The password, tried on the disk before it is taken. --test-passphrase opens
# nothing, it only asks the keyslots, and it takes the password on stdin the way
# the step that opens the disk does - never on a command line, which /proc would
# show. A simulated run is on somebody's own machine, whose disks are not ours
# to try.
unlocks_disk() {
    debugging && return 0
    printf '%s' "$ARCH_OS_RECOVERY_PASSWORD" | cryptsetup open --test-passphrase "$ROOT_PART"
}

# A LUKS header is readable without the password, so nobody is asked this.
disk_is_encrypted() {
    [ "$(fstype "$ROOT_PART")" = "crypto_LUKS" ] && echo true || echo false
}

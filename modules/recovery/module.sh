# What several scripts of the Recovery share, sourced in front of each after
# oak.sh. The functions the yaml calls by name are at the bottom.

# The name of the unlocked disk under /dev/mapper.
CRYPT=recovery

# The btrfs top level, where @ and the snapshots are and a rollback happens.
# Outside MNT, so it never ends up in a chroot and outlives an unmount there.
BTRFS_TOP=/run/arch-os-recovery

# ////////////////////////////////////////////////////////////////////////////
# WHAT THE DISK IS
# ////////////////////////////////////////////////////////////////////////////

# The second partition, where the Installer puts the system, taken only while
# it is a LUKS container or a btrfs labelled BTRFS. Raw output, so an empty
# column stays a column.
root_partition() {
    local part
    part="$(part_of "$ARCH_OS_RECOVERY_DISK" 2)"
    lsblk -dnro FSTYPE,LABEL "$part" 2>/dev/null | awk -F'[ ]' -v part="$part" '
        $1 == "crypto_LUKS" || ($1 == "btrfs" && $2 == "BTRFS") { print part }'
}
ROOT_PART="$(root_partition)"

# The unlocked mapper where the disk is encrypted, the partition where it is not.
root_device() {
    if [ "$ARCH_OS_RECOVERY_ENCRYPTED" = "true" ]; then
        printf '/dev/mapper/%s' "$CRYPT"
    else
        printf '%s' "$ROOT_PART"
    fi
}

# The device's own file system, --nodeps: without it an unlocked LUKS partition
# answers btrfs, from the layer on top.
fstype() { lsblk -dno FSTYPE "$1" 2>/dev/null || true; }

# ////////////////////////////////////////////////////////////////////////////
# MOUNTING & CLOSING
# ////////////////////////////////////////////////////////////////////////////

# The system mounted the way it mounts itself: @ first, /boot by its own fstab.
mount_target() {
    local subvolume path

    # @ first, since every other mount point is a directory inside it.
    while IFS=$'\t' read -r subvolume path; do
        mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=${subvolume}" "$(root_device)" "${MNT}${path%/}"
    done < <(btrfs_subvolumes)

    # As the system mounts it itself, with the options its own table gives it.
    mount --fstab "${MNT}/etc/fstab" --target-prefix "$MNT" --mkdir /boot
}

# Everything under /mnt taken down. Whatever still holds it is named in the log
# and killed; the second umount is meant to fail loudly. -R, not -A: the top
# level is a second mount of the same disk. -M keeps fuser on the target.
unmount_target() {
    mountpoint -q "$MNT" || return 0
    umount -R "$MNT" && return 0

    echo "the target did not unmount, what is holding it:"
    fuser -Mvm "$MNT" || true
    fuser -Mkm "$MNT" || true
    sleep 2 # the kernel needs a moment to actually let go of the files

    umount -R "$MNT"
}

# The system closed for good, before opening as after.
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

# Loaded the moment it is answered; a simulated run leaves the desk's alone.
load_console_keyboard() {
    debugging && return 0
    loadkeys "$ARCH_OS_RECOVERY_KEYMAP"
}

# Tried on the disk before it is taken, on stdin: --test-passphrase opens
# nothing, it only asks the keyslots.
unlocks_disk() {
    debugging && return 0
    printf '%s' "$ARCH_OS_RECOVERY_PASSWORD" | cryptsetup open --test-passphrase "$ROOT_PART"
}

# A LUKS header is readable without the password, so nobody is asked this.
disk_is_encrypted() {
    [ "$(fstype "$ROOT_PART")" = "crypto_LUKS" ] && echo true || echo false
}

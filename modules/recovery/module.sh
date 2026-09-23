# What more than one script of this module has to agree about, sourced by Oak in
# front of every one of them. Anything a single script needs stays in that
# script; the functions a declaration calls by name are at the bottom.

# Where the system being repaired is mounted, and what the unlocked disk is
# called under /dev/mapper.
MNT=/mnt
CRYPT=recovery

# A btrfs installation is two views of one disk: the system as it runs, mounted
# at MNT, and the top level holding @ and the snapshots, where a rollback
# happens. Kept out of MNT on purpose - it must not end up inside a chroot, and
# it must survive MNT being unmounted.
BTRFS_TOP=/run/arch-os-recovery

# ////////////////////////////////////////////////////////////////////////////
# WHAT THE DISK IS
# ////////////////////////////////////////////////////////////////////////////

# The installation on the chosen disk, found by the layout Arch OS always lays
# down - see part_of.
BOOT_PART="$(part_of "$ARCH_OS_RECOVERY_DISK" 1)"
ROOT_PART="$(part_of "$ARCH_OS_RECOVERY_DISK" 2)"

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

# Whether the system being repaired can be rolled back, which is the one thing
# here the file system decides. Read off the disk rather than answered: behind
# LUKS nothing can be seen until it is open, and every caller runs after that.
on_btrfs() { [ "$(fstype "$(root_device)")" = "btrfs" ]; }

# ////////////////////////////////////////////////////////////////////////////
# THE KERNELS ON THE DISK
# ////////////////////////////////////////////////////////////////////////////

# Which package a module directory belongs to: 6.12.4-arch1-1 is the stock
# kernel, anything carrying zen, lts or hardened is that one. Here because the
# repair puts the image back under this name and its test reads it back by the
# same one.
kernel_package() {
    case "$1" in
    *zen*) echo linux-zen ;;
    *lts*) echo linux-lts ;;
    *hardened*) echo linux-hardened ;;
    *) echo linux ;;
    esac
}

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
    local target present subvolume path
    target="$(root_device)"

    if on_btrfs; then
        # @ first: it is the root the rest are directories in, and the one
        # subvolume every installation has, so a missing one is a failure here.
        mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=@" "$target" "$MNT"

        # What this particular disk holds, named from the top level whichever
        # subvolume is mounted. The table is matched against it, so an older
        # layout is opened as far as it goes instead of refused.
        present="$(btrfs subvolume list "$MNT" | awk '{ print $NF }')"
        while IFS=$'\t' read -r subvolume path; do
            [ "$subvolume" = "@" ] && continue
            if ! printf '%s\n' "$present" | grep -qxF "$subvolume"; then
                echo "no ${subvolume} on this installation, leaving ${path} inside @"
                continue
            fi
            mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=${subvolume}" "$target" "${MNT}${path}"
        done < <(btrfs_subvolumes)
    else
        mount --mkdir "$target" "$MNT"
    fi

    mount --mkdir "$BOOT_PART" "${MNT}/boot"
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

# A LUKS header is readable without the password, so nobody is asked this.
disk_is_encrypted() {
    [ "$(fstype "$ROOT_PART")" = "crypto_LUKS" ] && echo true || echo false
}

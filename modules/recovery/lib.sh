# SHARED LIBRARY | Sourced by the runtime before every task and every hook
#
# Everything here is needed by more than one script and must not be answered
# twice - a second copy of a mount option or a partition number is a recovery
# that puts the system back together differently from how it was taken apart.
# Anything only one task needs stays in that task instead.
#
# Because this is sourced, every script here is plain shell with no preamble
# of its own - the ERR trap that stops on the first failure belongs to the
# runtime. Nothing in this file prints for a person to read, only to the log.
#
# Nothing here asks anything either: the keyboard, the disk, the password and
# the snapshot are questions in recovery.yaml, and this file is only ever
# handed the answers.

# Where the system being repaired is mounted.
MNT=/mnt

# A btrfs installation is two views of one disk: the system as it runs,
# mounted at MNT, and the top level holding @ and the snapshots, where a
# rollback happens. Kept out of MNT on purpose - it must not end up inside a
# chroot, and it must survive MNT being unmounted.
BTRFS_TOP=/run/arch-os-recovery

# What the unlocked disk is called under /dev/mapper.
CRYPT=recovery

# How this project mounts btrfs. The installer lays the file system out with
# these options, and this puts it back the same way - the two must not drift
# apart.
BTRFS_OPTS="defaults,noatime,compress=zstd"

# DEBUG=true runs the recovery without touching the machine. Each task guards
# itself with `simulating && return 0` as its first line, so a unit is only
# ever skipped as a whole.
: "${DEBUG:=false}"

simulating() {
    [ "$DEBUG" = "true" ] || return 1
    echo "simulated: ${BASH_SOURCE[1]}"
    sleep 1 # keep the step visible in the interface instead of flashing past
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# WHAT THE DISK IS CALLED
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# Names a partition of a disk. Devices whose name ends in a digit (nvme0n1,
# mmcblk0, loop0) get a p between the disk and the partition number.
part_of() {
    local sep=""
    [[ "$1" =~ [0-9]$ ]] && sep="p"
    printf '%s%s%s' "$1" "$sep" "$2"
}

# Arch OS always puts the EFI system partition first and the root second,
# whatever the disk is called.
boot_part() { part_of "$ARCH_OS_RECOVERY_DISK" 1; }
root_part() { part_of "$ARCH_OS_RECOVERY_DISK" 2; }

# What holds the file system: the unlocked mapper device where the disk is
# encrypted, the root partition itself where it isn't.
root_device() {
    if [ "$ARCH_OS_RECOVERY_ENCRYPTION_ENABLED" = "true" ]; then
        printf '/dev/mapper/%s' "$CRYPT"
    else
        root_part
    fi
}

# What a block device holds, or nothing for one that holds nothing readable.
# Asked before the disk is opened, to fill in the answers the questions
# offer, and again after, to check what turned up is what was answered.
fstype() { lsblk -no FSTYPE "$1" 2>/dev/null | head -n1; }

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# MOUNTING
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# The installed system, mounted exactly as it mounts itself. Shared because a
# rollback takes it apart to replace @ and then has to put it back together
# exactly as open left it.
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

# ---------------------------------------------------------------------------------------------------

# Everything this recovery had mounted, taken back down, and the disk locked
# again. Run before mounting as well as after, because a second attempt
# starts from a target the first may have left half open - and on the way
# out of the machine. Nothing here being mounted is the normal case, not an
# error.
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

# Whatever still has the system open, logged and then killed - typically a
# process a chroot left running. The sleep gives the kernel time to actually
# let go of the files afterwards.
#
# -M carries the whole safety of this: without it, a target that isn't
# itself a mount point resolves to the file system containing it, which on
# the live image is the live image itself.
free_target() {
    echo "the target did not unmount, what is holding it:"
    fuser -Mvm "$MNT" || true
    fuser -Mkm "$MNT" || true
    sleep 2
}

# THE MODULE'S SHELL | Sourced by Oak in front of everything this module runs
#
# Every task, and every piece of shell module.yaml writes for a list, a
# suggestion or a check, is given this file first - so a function named here is
# called from the yaml by name.
#
# Only what more than one script must agree about belongs in it: a second copy
# of a mount option or a partition number is a recovery that puts the system
# back together differently from how it was taken apart. Anything one task needs
# stays in that task. Nothing here prints for a person to read, only to the log.

# Where the system being repaired is mounted.
MNT=/mnt

# A btrfs installation is two views of one disk: the system as it runs, mounted
# at MNT, and the top level holding @ and the snapshots, where a rollback
# happens. Kept out of MNT on purpose - it must not end up inside a chroot, and
# it must survive MNT being unmounted.
BTRFS_TOP=/run/arch-os-recovery

# What the unlocked disk is called under /dev/mapper.
CRYPT=recovery

# How this project mounts btrfs. The installer lays the file system out with
# these options, and this puts it back the same way - the two must not drift
# apart.
BTRFS_OPTS="defaults,noatime,compress=zstd"

# ////////////////////////////////////////////////////////////////////////////
# SIMULATION
# ////////////////////////////////////////////////////////////////////////////

# --debug runs without touching the machine. Each task guards itself with
# `simulating && return 0` as its first line, so a unit is only ever skipped as
# a whole, and each test with `debugging && return 0` — a simulated run wrote
# nothing, so there is nothing on the machine for it to read.
#
# The pause is the difference between the two: it holds a step on screen long
# enough to be read instead of flashing past, and a test is not a step anybody
# is watching.

debugging() { [ "$DEBUG" = "true" ]; }

simulating() {
    debugging || return 1
    echo "simulated" # Oak has already logged which step this is
    sleep 1          # keep the step visible in the interface instead of flashing past
}

# ////////////////////////////////////////////////////////////////////////////
# WHAT THE DISK IS CALLED
# ////////////////////////////////////////////////////////////////////////////

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

# ////////////////////////////////////////////////////////////////////////////
# THE QUESTIONS | What module.yaml calls by name
# ////////////////////////////////////////////////////////////////////////////

# Every list a question offers and every value one opens on. They live here
# rather than in module.yaml because shell inside a yaml scalar is read by
# nobody and checked by nothing.
#
# Only the disk is really asked for; the rest is read off it and opens on that
# answer. They stay questions because behind LUKS nothing can be read until the
# password is given.

list_keymaps() { localectl list-keymaps; }

# The keyboard the live image was started with. The Arch image records it in
# root's shell history as the loadkeys command that set it, which is the only
# place it can be read back from.
default_keymap() {
    grep -h 'loadkeys' /root/.bash_history /root/.zsh_history 2>/dev/null |
        tail -n1 | sed 's/.*loadkeys *//' | tr -d ' ' || true
}

# The keyboard on the machine the recovery runs on, loaded the moment it is
# answered. A simulated run is on somebody's own machine, whose keyboard is not
# ours to touch.
load_console_keyboard() {
    [ "$DEBUG" = "true" ] && return 0
    loadkeys "$ARCH_OS_RECOVERY_KEYMAP"
}

# Whole disks only - 8 is SCSI and SATA, 259 NVMe, 254 virtual block devices.
# Nobody picks between /dev/sda and /dev/sdb by name, so the size and the model
# are what it is chosen by.
list_disks() {
    lsblk -d -n -I 8,259,254 -o PATH,SIZE,MODEL |
        awk '{ path = $1; $1 = ""; sub(/^ +/, ""); sub(/ +$/, ""); printf "%s\t%s  %s\n", path, path, $0 }'
}

# A LUKS header is readable without the password, so this one is reliable.
default_encryption() {
    [ "$(fstype "$(root_part)")" = "crypto_LUKS" ] && echo true || echo false
}

# Readable everywhere except behind LUKS, where the question is a real one.
default_filesystem() {
    case "$(fstype "$(root_part)")" in
    btrfs) echo btrfs ;;
    ext4) echo ext4 ;;
    esac
}

# ////////////////////////////////////////////////////////////////////////////
# MOUNTING & CLOSING
# ////////////////////////////////////////////////////////////////////////////

# The installed system, mounted exactly as it mounts itself. Shared because a
# rollback takes it apart to replace @ and then has to put it back together
# exactly as open left it.
mount_target() {
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

# ----------------------------------------------------------------------------

# Everything under /mnt, taken back down. Nothing mounted is not an error: a
# rollback takes the system apart with this in the middle of a run. Whatever
# still holds it is named in the log and then killed, and the second attempt is
# left unguarded on purpose - that one is a real failure.
#
# -M carries the whole safety of this: without it a target that isn't itself a
# mount point resolves to the file system containing it, which on the live image
# is the live image itself.
unmount_target() {
    mountpoint -q "$MNT" || return 0
    umount -A -R "$MNT" && return 0

    echo "the target did not unmount, what is holding it:"
    fuser -Mvm "$MNT" || true
    fuser -Mkm "$MNT" || true
    sleep 2 # the kernel needs a moment to actually let go of the files

    umount -A -R "$MNT"
}

# The system closed for good: swap off, everything unmounted and the disk locked
# again. Run before opening as well as after, because a second attempt starts
# from a target the first may have left half open.
close_target() {
    swapoff -a || true
    sync
    unmount_target || return 1 # a system still standing cannot be locked either
    mountpoint -q "$BTRFS_TOP" && umount -R "$BTRFS_TOP"
    [ -e "/dev/mapper/${CRYPT}" ] && cryptsetup close "$CRYPT"
    echo "closed ${MNT}"
}

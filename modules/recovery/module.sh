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

# How this project mounts btrfs, and what it laid down: subvolume, a tab, then
# where it belongs. The same table as the installer's, and the two must not
# drift apart - see docs/REFERENCE.md.
#
# Which of them a given system actually has is read off the disk rather than
# assumed: an installation from an earlier version has only the first three.
BTRFS_OPTS="defaults,noatime,compress=zstd"

btrfs_subvolumes() {
    printf '%s\t%s\n' \
        @ / \
        @home /home \
        @snapshots /.snapshots \
        @log /var/log \
        @cache /var/cache \
        @tmp /var/tmp
}

# ////////////////////////////////////////////////////////////////////////////
# SIMULATION
# ////////////////////////////////////////////////////////////////////////////

# --debug runs without touching the machine. Every task and every test opens on
# `simulating && return 0`: a task because there is nothing it may change, a
# test because a simulated run wrote nothing for it to read back.
#
# The pause holds each step on screen long enough to be read, which is what
# makes a simulated run something to watch — and what docs/screenshots.py
# photographs a run in the middle of.
#
# debugging is the bare question, for the few places that ask it without being
# a step: an answer applied to this machine, a list a page opens on.

debugging() { [ "$DEBUG" = "true" ]; }

simulating() {
    debugging || return 1
    echo "simulated"
    sleep 1
}

# ////////////////////////////////////////////////////////////////////////////
# WHAT THE DISK IS
# ////////////////////////////////////////////////////////////////////////////

# Arch OS always puts the EFI system partition first and the root second,
# whatever the disk is called - which is what lets this find an installation
# from the disk alone. Devices whose name ends in a digit (nvme0n1, mmcblk0) get
# a p between the disk and the partition number.
part_of() {
    local sep=""
    [[ "$1" =~ [0-9]$ ]] && sep="p"
    printf '%s%s%s' "$1" "$sep" "$2"
}

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

# Whether this is a booted Arch Linux live image, which is the only machine this
# module belongs on. Two markers, because either on its own is enough: /run/archiso
# is what the image mounts, archisobasedir is what it was booted with. And Arch
# on top of them, because an image built the same way by somebody else is not it.
arch_live() {
    { [ -d /run/archiso ] || grep -qs archisobasedir /proc/cmdline; } || return 1
    grep -qs '^ID=arch$' /etc/os-release
}

list_keymaps() { localectl list-keymaps; }

# The keyboard the live image was started with. The Arch image records it in
# root's shell history as the loadkeys command that set it, which is the only
# place it can be read back from - and finding nothing there is the ordinary
# case, because an image nobody ran loadkeys on is on the American layout.
#
# The fallback is what makes this answerable at all: with an empty suggestion
# the list opens on its own first row, which is 3l, and an enter meant for the
# page before it loads that. The next thing typed is the password that unlocks
# the disk, and it fails with nothing to say why.
default_keymap() {
    local keymap
    keymap="$({ grep -h 'loadkeys' /root/.bash_history /root/.zsh_history 2>/dev/null || true; } |
        tail -n1 | sed 's/.*loadkeys *//' | tr -d ' ')"
    printf '%s' "${keymap:-us}"
}

# Loaded the moment it is answered. A simulated run is on somebody's own
# machine, whose keyboard is not ours to touch.
load_console_keyboard() {
    debugging && return 0
    loadkeys "$ARCH_OS_RECOVERY_KEYMAP"
}

# The disk the live image is running from, or nothing where that cannot be read.
# It holds no installation to repair, and unlocking and mounting the medium the
# run is reading itself off is the one thing here that can end it.
#
# The same table the Installer reads, and the two must not drift apart.
live_disk() {
    lsblk -no PKNAME,MOUNTPOINT |
        awk '!found && $1 != "" && $2 ~ /^\/run\/archiso/ { print "/dev/" $1; found = 1 }'
}

# Whole disks only, asked of lsblk by what a device is rather than by the major
# number it was given: SATA, NVMe, eMMC, SD and a virtual disk are five numbers,
# one of which the kernel hands out at random - and a system installed on the
# eMMC is one this could not be pointed at.
#
# Nobody picks between /dev/sda and /dev/sdb by name, so the size and the model
# are what it is chosen by.
list_disks() {
    lsblk -dn -o PATH,TYPE,SIZE,MODEL | awk -v live="$(live_disk)" '
        $2 != "disk" || $1 == live || $1 ~ /^\/dev\/zram/ { next }
        { path = $1; $1 = ""; $2 = ""; sub(/^ +/, ""); sub(/ +$/, ""); printf "%s\t%s  %s\n", path, path, $0 }'
}

# A LUKS header is readable without the password, so nobody is asked this.
disk_is_encrypted() {
    [ "$(fstype "$ROOT_PART")" = "crypto_LUKS" ] && echo true || echo false
}

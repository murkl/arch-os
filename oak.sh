# shellcheck shell=bash
# What the modules of Arch OS have to agree about with each other, loaded by Oak
# in front of every script of every one of them and before that module's own
# module.sh. What only one module needs stays in that module.
#
# https://github.com/murkl/oak/blob/main/docs/REFERENCE.md

# Whether this run only pretends to work. Oak starts no task under --debug, so
# this is for the few places that still run there and must not touch the
# machine: an answer applied to it, a list a page opens on, a task that
# simulates itself.
debugging() { [ "$DEBUG" = "true" ]; }

# Everything a module downloads, https even after a redirect: -L on its own
# would follow a 302 into plain http, where the answer is whoever is on the wire.
# A connect timeout, so a machine behind a black hole says so rather than hangs.
fetch_url() {
    curl -Lf --proto '=https' --proto-redir '=https' --connect-timeout 10 "$@"
}

# ////////////////////////////////////////////////////////////////////////////
# THE LIVE IMAGE
# ////////////////////////////////////////////////////////////////////////////

# Whether this is a booted Arch Linux live image, which the Installer and the
# Recovery belong on and Create boot medium does not. Two markers, because
# either on its own is enough: /run/archiso is what the image mounts,
# archisobasedir is what it was booted with.
on_live_image() {
    [ -d /run/archiso ] || grep -qs archisobasedir /proc/cmdline
}

# And Arch on top of them, because an image built the same way by somebody else
# is not the system Arch OS installs or repairs.
arch_live() {
    on_live_image || return 1
    grep -qs '^ID=arch$' /etc/os-release
}

# The keyboard the live image was started with. The Arch image records it only
# as the loadkeys command in root's shell history, and finding nothing there is
# the ordinary case - an image nobody ran loadkeys on is on the American
# layout - so the grep must not make a failure of it: pipefail would carry that
# out of the whole lookup.
live_keymap() {
    local keymap
    keymap="$({ grep -h 'loadkeys' /root/.bash_history /root/.zsh_history 2>/dev/null || true; } |
        tail -n1 | sed 's/.*loadkeys *//' | tr -d ' ')"
    printf '%s' "${keymap:-us}"
}

# The disk the live image is running from, or nothing where that cannot be read.
# Every part of the image is reached through it for as long as the run lasts, so
# it is the one disk no module may write to or open. Read off the mount table
# rather than off the boot medium's name, because that is also how an image
# booted through Ventoy says which disk it came from.
live_disk() {
    lsblk -no PKNAME,MOUNTPOINT |
        awk '!found && $1 != "" && $2 ~ /^\/run\/archiso/ { print "/dev/" $1; found = 1 }'
}

# Whole disks only, asked of lsblk by what a device is rather than by the major
# number it was given: SATA, NVMe, eMMC, SD and a virtual disk are five numbers,
# one of which the kernel hands out at random - and a disk nobody can choose is
# a machine nobody can install onto or repair.
#
# Nobody picks between /dev/sda and /dev/sdb by name, so the size and the model
# are what it is chosen by.
list_disks() {
    lsblk -dn -o PATH,TYPE,SIZE,MODEL | awk -v live="$(live_disk)" '
        $2 != "disk" || $1 == live || $1 ~ /^\/dev\/zram/ { next }
        { path = $1; $1 = ""; $2 = ""; sub(/^ +/, ""); sub(/ +$/, ""); printf "%s\t%s  %s\n", path, path, $0 }'
}

# ////////////////////////////////////////////////////////////////////////////
# THE SIGNED BOOT CHAIN
# ////////////////////////////////////////////////////////////////////////////

# Whether every file sbctl keeps in the system mounted at $1 is signed, and
# there is a file at all - what the Installer signs and the Recovery signs again
# after a rebuild. Read out of sbctl's own list, because `sbctl verify` answers
# 0 whatever it found, and `sbctl sign-all` over an empty database signs nothing
# without a word. Either leaves a machine that Secure Boot refuses to start.
boot_chain_signed() {
    local files
    files="$(arch-chroot "$1" sbctl list-files --json)" || return 1
    if ! grep -q '"is_signed": true' <<<"$files"; then
        echo "sbctl keeps no signed file" >&2
        return 1
    fi
    if grep -q '"is_signed": false' <<<"$files"; then
        echo "sbctl keeps files that are not signed: ${files}" >&2
        return 1
    fi
}

# ////////////////////////////////////////////////////////////////////////////
# THE DISK LAYOUT
# ////////////////////////////////////////////////////////////////////////////

# Names a partition of a disk as the Installer lays it out: the EFI system
# partition first, the root second - see docs/REFERENCE.md. A disk whose name
# ends in a digit (nvme0n1, mmcblk0, loop0) gets a p between it and the number.
part_of() {
    local sep=""
    [[ "$1" =~ [0-9]$ ]] && sep="p"
    printf '%s%s%s' "$1" "$sep" "$2"
}

# How Arch OS mounts btrfs, and what it lays down: subvolume, a tab, then where
# it belongs. The Installer creates every one of them; the Recovery mounts
# whichever of them an installation actually has, since an older one may have
# fewer. Why the four under /var are separate: docs/REFERENCE.md
#
# Read by the modules' scripts, which shellcheck reads one at a time, so the
# option string looks unused here.
# shellcheck disable=SC2034
BTRFS_OPTS="defaults,noatime,compress=zstd"

btrfs_subvolumes() {
    printf '%s\t%s\n' \
        @ / \
        @home /home \
        @snapshots /.snapshots \
        @log /var/log \
        @cache /var/cache \
        @tmp /var/tmp \
        @libvirt /var/lib/libvirt/images
}

# The live system made ready to install from. Nothing here touches the target
# disk: it ranks the mirrors everything after this downloads from, undoes what a
# previous attempt left mounted and brings the keyring up to date.

# What this machine is, in one line, before anything else is written down. Every
# question asked of the log afterwards - was there memory, was there room, is
# this a guest - is answered here instead of guessed at.
printf 'machine: %s cores, %s memory, %s on %s, virtualisation %s\n' \
    "$(nproc)" \
    "$(awk '/^MemTotal:/ { printf "%.1f GiB", $2 / 1048576 }' /proc/meminfo)" \
    "$(lsblk -bdno SIZE "$ARCH_OS_DISK" | numfmt --to=iec)" \
    "$ARCH_OS_DISK" \
    "$(systemd-detect-virt || true)"

# The Arch live image ships reflector but runs it nowhere: its mirrorlist is the
# stock worldwide one, four hundred servers in no order, and pacstrap copies
# that file into the new system. So without this both the installation and every
# update afterwards download from whatever server happens to be first.
# https://wiki.archlinux.org/title/Reflector
#
# Written to a file of its own and moved into place only when it worked, because
# reflector writes its output as it goes. Never fatal - a slow mirror installs,
# no mirror list at all does not.
rank_mirrors() {
    command -v reflector >/dev/null || {
        echo "this image has no reflector, installing from the list it shipped" >&2
        return 0
    }

    local ranked warnings servers unrated args=(--protocol https --age 12 --latest 10 --sort rate)
    [ -n "$ARCH_OS_REFLECTOR_COUNTRY" ] && args+=(--country "$ARCH_OS_REFLECTOR_COUNTRY")
    ranked="$(mktemp)"
    warnings="$(mktemp)"

    # A mirror that does not answer within reflector's own timeout is kept rather
    # than dropped, with one warning for it - and a list where every one timed
    # out is still written, in no order, with exit 0. That list is worse than the
    # one the image shipped, which opens on Arch's own CDN.
    if timeout 120 reflector "${args[@]}" --save "$ranked" 2>"$warnings" && [ -s "$ranked" ]; then
        servers="$(grep -c '^Server' "$ranked" || true)"
        unrated="$(grep -c 'failed to rate' "$warnings" || true)"
        if [ "$servers" -gt "$unrated" ]; then
            install -m 644 "$ranked" /etc/pacman.d/mirrorlist
            echo "installing from ${servers} ranked mirrors"
        else
            echo "none of the ${servers} mirrors answered in time to be ranked, installing from the list the image shipped" >&2
        fi
    else
        echo "the mirrors could not be ranked, installing from the list the image shipped" >&2
    fi
    cat "$warnings" >&2
    rm -f "$ranked" "$warnings"
}

echo "ranking mirrors"
rank_mirrors

timedatectl set-ntp true

# Some old routers drop connections that use it, which shows up as an install
# stalling partway through a download.
[ "$ARCH_OS_ECN_ENABLED" = "false" ] && sysctl net.ipv4.tcp_ecn=0

# What a previous attempt left behind. A target that will not come down is a
# failure here, because the next stage partitions the disk under it.
close_target

# An LVM group the live image activated on its own, off whatever was on the disk
# before. Nothing here creates one; an active one holds the partition open. Oak's
# error channel is closed for it, because lvm warns about every file descriptor
# it was handed and prints the whole of what opened it.
vgchange -an 3>&- || true

# And the same for a software RAID, which udev assembles on its own off the
# superblock a disk out of an old machine still carries: the array then holds
# the partition open and the next stage cannot even repartition it. Nothing is
# mounted on a live image, so there is nothing to lose by stopping every one of
# them; an array that will not stop is left to the failure it causes later,
# where the message names the disk.
if command -v mdadm >/dev/null; then
    mdadm --stop --scan || true
fi

rm -f /var/lib/pacman/db.lck

# A stale keyring is the commonest reason a fresh install refuses to verify a
# package it just downloaded.
pacman -Sy --noconfirm archlinux-keyring

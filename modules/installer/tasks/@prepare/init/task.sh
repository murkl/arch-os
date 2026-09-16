# Make the live system ready to install from. Nothing here touches the target
# disk: it ranks the mirrors everything after this downloads from, undoes what a
# previous attempt left mounted and brings the keyring up to date.

simulating && return 0

# What this machine is, in one line, before anything else is written down. Every
# failure after this is read out of the same log, and almost every question
# asked of one - was there memory, was there room, is this a guest - is answered
# here instead of guessed at afterwards.
printf 'machine: %s cores, %s memory, %s on %s, virtualisation %s\n' \
    "$(nproc)" \
    "$(awk '/^MemTotal:/ { printf "%.1f GiB", $2 / 1048576 }' /proc/meminfo)" \
    "$(lsblk -bdno SIZE "$ARCH_OS_DISK" | numfmt --to=iec)" \
    "$ARCH_OS_DISK" \
    "$(systemd-detect-virt || true)"

# The mirrors, ranked once, here. The Arch live image ships reflector but runs it
# nowhere: its mirrorlist is the stock worldwide one, four hundred servers in no
# order, and pacstrap copies that file into the new system - so without this both
# the installation and every update afterwards download from whatever server
# happens to be first. This is also what makes the mirror country a real answer
# rather than a setting only a weekly timer ever reads.
#
# Written to a file of its own and moved into place only when it worked: a
# ranking that times out or finds no mirror in that country must leave the list
# it was given, and reflector writes its output as it goes. Never fatal - a slow
# mirror installs, no mirror list at all does not.
rank_mirrors() {
    command -v reflector >/dev/null || {
        echo "this image has no reflector, installing from the list it shipped" >&2
        return 0
    }

    local ranked args=(--protocol https --age 12 --latest 10 --sort rate)
    [ -n "$ARCH_OS_REFLECTOR_COUNTRY" ] && args+=(--country "$ARCH_OS_REFLECTOR_COUNTRY")
    ranked="$(mktemp)"

    if timeout 120 reflector "${args[@]}" --save "$ranked" && [ -s "$ranked" ]; then
        install -m 644 "$ranked" /etc/pacman.d/mirrorlist
        echo "installing from $(grep -c '^Server' /etc/pacman.d/mirrorlist) ranked mirrors"
    else
        echo "the mirrors could not be ranked, installing from the list the image shipped" >&2
    fi
    rm -f "$ranked"
}

echo "ranking mirrors"
rank_mirrors

timedatectl set-ntp true

# Some old routers drop connections that use it, which shows up as an install
# stalling partway through a download.
[ "$ARCH_OS_ECN_ENABLED" = "false" ] && sysctl net.ipv4.tcp_ecn=0

# What a previous attempt left behind, closed the same way this run will close
# the target at the end. A first run finds nothing to close, which is not an
# error - but a target that will not come down is, because the next stage
# partitions the disk under it.
close_target

# An LVM group the live image activated on its own, off whatever was on the disk
# before. Nothing here creates one; an active one holds the partition open.
#
# Oak's error channel is closed for it: lvm warns about every file descriptor it
# was handed and prints the whole of what opened it, which puts a page of Oak's
# own trap in the log for nothing.
vgchange -an 3>&- || true

rm -f /var/lib/pacman/db.lck

# A stale keyring is the commonest reason a fresh install refuses to verify a
# package it just downloaded.
pacman -Sy --noconfirm archlinux-keyring

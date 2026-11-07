# Limits and no timeline: docs/REFERENCE.md#snapshots
# https://wiki.archlinux.org/title/Snapper

# snapper creates /.snapshots itself, so the subvolume is unmounted around
# create-config and mounted again.
run arch-chroot "$MNT" umount /.snapshots
run arch-chroot "$MNT" rm -r /.snapshots
run arch-chroot "$MNT" snapper --no-dbus -c root create-config /
run arch-chroot "$MNT" btrfs subvolume delete /.snapshots
run arch-chroot "$MNT" mkdir /.snapshots
run arch-chroot "$MNT" mount -a

# Root only, as snapper creates it. snapper runs through sudo: an allowed group
# could delete every snapshot through snapperd without a password.
run arch-chroot "$MNT" chmod 750 /.snapshots

# One argument per setting: given one string, set-config silently writes it all
# into the first key.
mapfile -t settings <"$(where)/settings"
run arch-chroot "$MNT" snapper --no-dbus -c root set-config "${settings[@]}"

# create-config enables the timeline timer, and set-config leaves it enabled.
run arch-chroot "$MNT" systemctl disable snapper-timeline.timer

run arch-chroot "$MNT" systemctl enable snapper-cleanup.timer

chroot_pacman_install snap-pac

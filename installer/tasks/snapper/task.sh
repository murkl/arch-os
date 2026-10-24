# A snapshot before every package transaction, cleaned up on a timer. Why these
# limits and no timeline: docs/REFERENCE.md#snapshots
# https://wiki.archlinux.org/title/Snapper

# snapper insists on creating /.snapshots itself, so the subvolume is taken away
# and put back around it.
arch-chroot "$MNT" umount /.snapshots
arch-chroot "$MNT" rm -r /.snapshots
arch-chroot "$MNT" snapper --no-dbus -c root create-config /
arch-chroot "$MNT" btrfs subvolume delete /.snapshots
arch-chroot "$MNT" mkdir /.snapshots
arch-chroot "$MNT" mount -a

# Root's alone, as snapper makes it. snapper itself is run through sudo: a group
# it allows could delete every snapshot through its daemon without a password.
arch-chroot "$MNT" chmod 750 /.snapshots

# One argument per setting: handed one string, set-config writes it all into
# the first key and says nothing.
mapfile -t settings <"$(where)/settings"
arch-chroot "$MNT" snapper --no-dbus -c root set-config "${settings[@]}"

# create-config switched the timeline timer on for the template's timeline, and
# set-config leaves it on.
arch-chroot "$MNT" systemctl disable snapper-timeline.timer

arch-chroot "$MNT" systemctl enable snapper-cleanup.timer

chroot_pacman_install snap-pac

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
arch-chroot "$MNT" chmod 750 /.snapshots
arch-chroot "$MNT" chown :wheel /.snapshots

# One argument per setting: handed one string, set-config writes it all into
# the first key and says nothing.
mapfile -t settings <"$(where)/settings"
arch-chroot "$MNT" snapper --no-dbus -c root set-config "${settings[@]}"

# btrfs commits freed extents on its own schedule, and df shows the disk full
# until it does. ExecStopPost, since the unit is Type=simple.
mkdir -p "${MNT}/etc/systemd/system/snapper-cleanup.service.d"
render "$(where)/sync.conf" >"${MNT}/etc/systemd/system/snapper-cleanup.service.d/sync.conf"
arch-chroot "$MNT" systemctl enable snapper-cleanup.timer

chroot_pacman_install snap-pac

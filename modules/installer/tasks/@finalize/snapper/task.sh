# Snapshots taken before every package transaction and cleaned up on a timer, so
# an update that goes wrong can be rolled back without the disk filling up.
# https://wiki.archlinux.org/title/Snapper

# snapper insists on creating /.snapshots itself, so the subvolume mounted there
# is taken away and put back around it.
arch-chroot "$MNT" umount /.snapshots
arch-chroot "$MNT" rm -r /.snapshots
arch-chroot "$MNT" snapper --no-dbus -c root create-config /
arch-chroot "$MNT" btrfs subvolume delete /.snapshots
arch-chroot "$MNT" mkdir /.snapshots
arch-chroot "$MNT" mount -a
arch-chroot "$MNT" chmod 750 /.snapshots
arch-chroot "$MNT" chown :wheel /.snapshots

# One argument per setting, from module.sh: set-config reads each of them as
# KEY=VALUE, and a whole line handed to it as one string lands in the first key
# as text.
mapfile -t settings < <(snapper_config)
arch-chroot "$MNT" snapper --no-dbus -c root set-config "${settings[@]}"

# A cleanup frees extents, but btrfs commits that on its own schedule: until it
# does, df reports the disk as full as it was. ExecStopPost rather than
# ExecStartPost, because the unit is Type=simple.
mkdir -p "${MNT}/etc/systemd/system/snapper-cleanup.service.d"
render "$(where)/sync.conf" >"${MNT}/etc/systemd/system/snapper-cleanup.service.d/sync.conf"

# No timeline and no snapshot at every boot: between two package transactions
# the system changes only where a snapshot of it should not follow - disk
# images, containers, databases - and those would be held in every one of them.
arch-chroot "$MNT" systemctl enable snapper-cleanup.timer

# snapper's own hook: named snapshots, cleaned up by the timer above.
chroot_pacman_install snap-pac

# There has to be somewhere for a snapshot to go, and something that takes one.
arch-chroot "$MNT" test -d /.snapshots
if [ "$ARCH_OS_BTRFS_SNAPPER_ENABLED" = "true" ]; then
    arch-chroot "$MNT" snapper --no-dbus -c root get-config >/dev/null
else
    [ -f "${MNT}/etc/pacman.d/hooks/50-btrfs-snapshot.hook" ]
fi

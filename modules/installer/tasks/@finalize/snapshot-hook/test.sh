# There has to be somewhere for a snapshot to go, and something that takes one.
debugging && return 0

arch-chroot "$MNT" test -d /.snapshots
[ -f "${MNT}/etc/pacman.d/hooks/50-btrfs-snapshot.hook" ]

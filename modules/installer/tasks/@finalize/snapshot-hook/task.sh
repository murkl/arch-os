# Without snapper the file system can still snapshot itself: one dated read-only
# snapshot per package transaction, and nothing cleaning up after it.

simulating && return 0

mkdir -p "${MNT}/etc/pacman.d/hooks"
render "$(where)/50-btrfs-snapshot.hook" >"${MNT}/etc/pacman.d/hooks/50-btrfs-snapshot.hook"

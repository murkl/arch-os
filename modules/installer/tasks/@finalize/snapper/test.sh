# There has to be somewhere for a snapshot to go, and a configuration snapper
# itself answers for - a directory alone is a snapshot nothing ever takes.
simulating && return 0

arch-chroot "$MNT" test -d /.snapshots
arch-chroot "$MNT" snapper --no-dbus -c root get-config >/dev/null

# A scrub reads every block back and checks it against its checksum, which is
# what turns a disk going bad into something noticed before a file is asked for.
# The timer comes with btrfs-progs, which the base system already has.
#
# One timer, not one per subvolume: a scrub verifies the whole file system, so
# the subvolumes would only be repeated passes over the same disk. The `-` is
# how a systemd unit spells the mount point /.

simulating && return 0

arch-chroot "$MNT" systemctl enable btrfs-scrub@-.timer

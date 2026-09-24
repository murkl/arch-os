# A scrub reads every block back and checks it against its checksum, which turns
# a disk going bad into something noticed before a file is asked for. One timer
# and not one per subvolume: a scrub verifies the whole file system. The `-` is
# how a systemd unit spells the mount point /.
# https://wiki.archlinux.org/title/Btrfs#Scrub

arch-chroot "$MNT" systemctl enable btrfs-scrub@-.timer

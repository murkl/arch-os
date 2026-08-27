# The services a working system runs, switched on so the first boot comes up
# with a network, a clock and a swap.

simulating && return 0

arch-chroot "$MNT" systemctl enable NetworkManager
arch-chroot "$MNT" systemctl enable fstrim.timer                     # keeps an SSD fast
arch-chroot "$MNT" systemctl enable systemd-zram-setup@zram0.service # the swap configure-system set up
arch-chroot "$MNT" systemctl enable systemd-oomd.service             # kills a runaway before the machine locks up
arch-chroot "$MNT" systemctl enable systemd-timesyncd.service

if [ "$ARCH_OS_FILESYSTEM" = "btrfs" ]; then
    # Monthly verification of every checksum on the file system.
    arch-chroot "$MNT" systemctl enable btrfs-scrub@-.timer
    arch-chroot "$MNT" systemctl enable btrfs-scrub@home.timer
    arch-chroot "$MNT" systemctl enable btrfs-scrub@snapshots.timer
fi

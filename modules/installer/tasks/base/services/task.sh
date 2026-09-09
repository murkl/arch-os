# The services a working system runs, switched on so the first boot comes up
# with a network, a clock and a swap.

simulating && return 0

arch-chroot "$MNT" systemctl enable NetworkManager
arch-chroot "$MNT" systemctl enable fstrim.timer                     # keeps an SSD fast
arch-chroot "$MNT" systemctl enable systemd-zram-setup@zram0.service # the swap configure-system set up
arch-chroot "$MNT" systemctl enable systemd-oomd.service             # kills a runaway before the machine locks up
arch-chroot "$MNT" systemctl enable systemd-timesyncd.service

# One timer, not one per subvolume: a scrub verifies the whole file system, so
# the subvolumes would only be three passes over the same disk.
if [ "$ARCH_OS_FILESYSTEM" = "btrfs" ]; then
    arch-chroot "$MNT" systemctl enable btrfs-scrub@-.timer
fi

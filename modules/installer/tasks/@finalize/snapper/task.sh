# Snapshots of the system, taken before every package transaction and cleaned up
# on a timer - so an update that goes wrong can be rolled back from the boot
# menu without the disk filling up over the months.
#
# Its own task beside the plain hook rather than a branch inside a shared one:
# the two are different answers to one question, and which of them runs is
# written in the yaml rather than read out of shell.

simulating && return 0

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

# Snapper's defaults are written for a system that changes slowly. A rolling
# release is not one: every snapshot pins the package versions it was taken
# over as data nothing else can free, and fifty of them plus a year of
# timeline is how a disk fills up - measured on one machine after nine
# months, 70G held against 35G of actual system. A rollback is for the
# update that just broke something, which is days rather than months.
arch-chroot "$MNT" snapper --no-dbus -c root set-config \
    "NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5 TIMELINE_LIMIT_MONTHLY=2 TIMELINE_LIMIT_YEARLY=0"

# A cleanup frees extents, but btrfs commits that on its own schedule: until it
# does, df reports the disk as full as it was.
#
# ExecStopPost rather than ExecStartPost because the unit is Type=simple, where a
# post-start command runs the moment the cleanup is launched.
mkdir -p "${MNT}/etc/systemd/system/snapper-cleanup.service.d"
{
    echo "# Written by the Arch OS Installer."
    echo "[Service]"
    echo "ExecStopPost=/usr/bin/sync"
    echo "ExecStopPost=/usr/bin/btrfs filesystem sync /"
} >"${MNT}/etc/systemd/system/snapper-cleanup.service.d/sync.conf"

arch-chroot "$MNT" systemctl enable snapper-timeline.timer
arch-chroot "$MNT" systemctl enable snapper-cleanup.timer
arch-chroot "$MNT" systemctl enable snapper-boot.timer

# snapper's own hook: named snapshots, cleaned up by the timers above.
chroot_pacman_install snap-pac

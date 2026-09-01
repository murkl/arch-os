# Snapper, which keeps a rolling set of snapshots of the system and cleans them
# up again on a timer.

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

# Snapper's own limits are written for a system that changes slowly. This one
# does not: a rolling release brings a new kernel, a new browser and a new JDK
# every few weeks, and every snapshot pins the versions it was taken over as
# copy-on-write data nothing else can free. Fifty of those plus a year of
# timeline is how a disk fills with packages nobody has run in months — measured
# on one machine after nine months: 70G held against 35G of actual system.
#
# So: fewer of them, and none kept for a year. What a rollback is for is the
# update that just broke something, and that is measured in days. The settings
# go in as one argument, which is the form snapper(8) documents.
arch-chroot "$MNT" snapper --no-dbus -c root set-config \
    "NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5 TIMELINE_LIMIT_MONTHLY=2 TIMELINE_LIMIT_YEARLY=0"

# A cleanup frees extents, but btrfs commits that on its own schedule: until it
# does, df reports a disk as full as it was, which reads as a cleanup that did
# nothing — and is the reason somebody goes looking for the space by hand.
#
# ExecStopPost rather than ExecStartPost because the unit is Type=simple: a
# post-start command would run the moment the cleanup was launched, not once it
# had finished.
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

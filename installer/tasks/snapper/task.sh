# Limits and no timeline: docs/REFERENCE.md#snapshots
# https://wiki.archlinux.org/title/Snapper

# snapper creates /.snapshots itself, so the subvolume is unmounted around
# create-config and mounted again.
run arch-chroot "$MNT" umount /.snapshots
run arch-chroot "$MNT" rm -r /.snapshots
run arch-chroot "$MNT" snapper --no-dbus -c root create-config /
run arch-chroot "$MNT" btrfs subvolume delete /.snapshots
run arch-chroot "$MNT" mkdir /.snapshots
run arch-chroot "$MNT" mount -a

# Root only, as snapper creates it. snapper runs through sudo: an allowed group
# could delete every snapshot through snapperd without a password.
run arch-chroot "$MNT" chmod 750 /.snapshots

# One argument per setting: given one string, set-config silently writes it all
# into the first key.
mapfile -t settings <"$(where)/settings"
run arch-chroot "$MNT" snapper --no-dbus -c root set-config "${settings[@]}"

# create-config enables the timeline timer, and set-config leaves it enabled.
run arch-chroot "$MNT" systemctl disable snapper-timeline.timer

run arch-chroot "$MNT" systemctl enable snapper-cleanup.timer

# One more snapshot per good start, which also holds changes made by hand.
run mkdir -p "${MNT}/usr/local/lib/arch-os"
render "$(where)/boot-snapshot.sh" | write_file "${MNT}/usr/local/lib/arch-os/boot-snapshot.sh"
run chmod 755 "${MNT}/usr/local/lib/arch-os/boot-snapshot.sh"
render "$(where)/arch-os-boot-snapshot.service" | write_file "${MNT}/etc/systemd/system/arch-os-boot-snapshot.service"
run arch-chroot "$MNT" systemctl enable arch-os-boot-snapshot.service

chroot_pacman_install snap-pac

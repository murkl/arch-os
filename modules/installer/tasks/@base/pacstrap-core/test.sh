# A system on the disk is a package database and a kernel to boot.
simulating && return 0

[ -x "${MNT}/usr/bin/pacman" ]
[ -f "${MNT}/boot/vmlinuz-${ARCH_OS_KERNEL}" ]

# And a file system table, read by the tool that will read it at boot rather
# than looked at. genfstab writes what happened to be mounted when it ran, so a
# table missing either of these is a machine that comes up in an emergency
# shell - and nothing between here and the first restart would notice.
findmnt --fstab --tab-file "${MNT}/etc/fstab" / >/dev/null
findmnt --fstab --tab-file "${MNT}/etc/fstab" /boot >/dev/null

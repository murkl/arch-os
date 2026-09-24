# A system on the disk is a package database and a kernel to boot.

[ -x "${MNT}/usr/bin/pacman" ]
[ -f "${MNT}/boot/vmlinuz-${ARCH_OS_KERNEL}" ]

# And a file system table, read by the tool that will read it at boot rather
# than looked at. genfstab writes what happened to be mounted when it ran, so a
# table missing either of these is a machine that comes up in an emergency
# shell - and nothing between here and the first restart would notice.
findmnt --fstab --tab-file "${MNT}/etc/fstab" / >/dev/null

# And /boot as root's alone. The sed that sets it matches the options genfstab
# writes today, and says nothing the day they are spelled another way.
boot_options="$(findmnt --fstab --tab-file "${MNT}/etc/fstab" -no OPTIONS /boot)"
grep -qE '(^|,)fmask=0077(,|$)' <<<"$boot_options"
grep -qE '(^|,)dmask=0077(,|$)' <<<"$boot_options"

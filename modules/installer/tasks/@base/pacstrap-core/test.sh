# A system on the disk is a package database and a kernel to boot.
debugging && return 0

[ -x "${MNT}/usr/bin/pacman" ]
[ -f "${MNT}/boot/vmlinuz-${ARCH_OS_KERNEL}" ]

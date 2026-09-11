# A system on the disk is a package database and a kernel to boot.
[ -x "${MNT}/usr/bin/pacman" ]
[ -f "${MNT}/boot/vmlinuz-${ARCH_OS_KERNEL}" ]

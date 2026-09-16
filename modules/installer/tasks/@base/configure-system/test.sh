# What the run has to be able to read back off the new system: its own name, its
# language, a clock that points somewhere, a network to come up on, and swap
# settings the kernel will actually act on - sysctl says nothing about a key it
# has never heard of, so a renamed one is a file that looks right and does
# nothing.
debugging && return 0

grep -qx "$ARCH_OS_HOSTNAME" "${MNT}/etc/hostname"
grep -qx "LANG=${ARCH_OS_LOCALE_LANG}.UTF-8" "${MNT}/etc/locale.conf"
[ -f "${MNT}/etc/localtime" ]
sysctl_keys_exist "${MNT}/etc/sysctl.d/99-vm-zram-parameters.conf"
arch-chroot "$MNT" systemctl is-enabled NetworkManager >/dev/null

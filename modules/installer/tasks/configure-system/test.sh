# What the run has to be able to read back off the new system: its own name, its
# language, a clock that points somewhere, and a network to come up on.
grep -qx "$ARCH_OS_HOSTNAME" "${MNT}/etc/hostname"
grep -qx "LANG=${ARCH_OS_LOCALE_LANG}.UTF-8" "${MNT}/etc/locale.conf"
[ -f "${MNT}/etc/localtime" ]
arch-chroot "$MNT" systemctl is-enabled NetworkManager >/dev/null

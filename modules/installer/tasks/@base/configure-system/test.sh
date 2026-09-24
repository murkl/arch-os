# What has to be readable back off the new system: its own name, its language, a
# clock that points somewhere, an editor that exists, a network to come up on,
# and swap settings the kernel will actually act on.

grep -qx "$ARCH_OS_HOSTNAME" "${MNT}/etc/hostname"
grep -qx "LANG=${ARCH_OS_LOCALE_LANG}.UTF-8" "${MNT}/etc/locale.conf"
[ -f "${MNT}/etc/localtime" ]

# An $EDITOR naming a command nobody installed looks exactly like a correct
# line, so it is looked for in the system that will run it.
editor="$(sed -n 's/^EDITOR=//p' "${MNT}/etc/environment")"
[ -n "$editor" ]
has_command "$editor"
sysctl_keys_exist "${MNT}/etc/sysctl.d/99-vm-zram-parameters.conf"
arch-chroot "$MNT" systemctl is-enabled NetworkManager >/dev/null

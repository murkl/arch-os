# What the run has to be able to read back off the new system: its own name, its
# language, a clock that points somewhere, an editor that exists, a network to
# come up on, and swap settings the kernel will actually act on - sysctl says
# nothing about a key it has never heard of, so a renamed one is a file that
# looks right and does nothing.
debugging && return 0

grep -qx "$ARCH_OS_HOSTNAME" "${MNT}/etc/hostname"
grep -qx "LANG=${ARCH_OS_LOCALE_LANG}.UTF-8" "${MNT}/etc/locale.conf"
[ -f "${MNT}/etc/localtime" ]

# The editor, read out of the file the way pam_env reads it, and looked for in
# the system that will run it: an $EDITOR naming a command nobody installed is
# the failure worth catching, and it looks exactly like a correct line.
editor="$(sed -n 's/^EDITOR=//p' "${MNT}/etc/environment")"
[ -n "$editor" ]
has_command "$editor"
sysctl_keys_exist "${MNT}/etc/sysctl.d/99-vm-zram-parameters.conf"
arch-chroot "$MNT" systemctl is-enabled NetworkManager >/dev/null

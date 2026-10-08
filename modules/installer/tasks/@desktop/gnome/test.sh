arch-chroot "$MNT" systemctl is-enabled gdm.service >/dev/null

has_command gnome-software

arch-chroot "$MNT" systemctl --global is-enabled pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null

# Without the module the daemon runs and nothing reaches a .local name.
grep -q 'mdns_minimal' "${MNT}/etc/nsswitch.conf"
[ "$ARCH_OS_FIREWALL_ENABLED" != "true" ] ||
    arch-chroot "$MNT" firewall-offline-cmd --zone=public --query-service=mdns >/dev/null

has_command seahorse

# Automatic login exactly where the boot password stands in front and is the
# account's too: docs/REFERENCE.md#accounts
autologin=false
grep -qs '^AutomaticLoginEnable=True' "${MNT}/etc/gdm/custom.conf" && autologin=true
if [ "$autologin" = "true" ] && [ "$ARCH_OS_ENCRYPTION_ENABLED" != "true" ]; then
    echo "the disk is not encrypted and the login is automatic" >&2
    exit 1
fi
if [ "$autologin" = "true" ] && [ "$ARCH_OS_DISK_PASSWORD_ENABLED" = "true" ]; then
    echo "the disk has a password of its own and the login is automatic" >&2
    exit 1
fi
if [ "$autologin" = "false" ] && [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && [ "$ARCH_OS_DISK_PASSWORD_ENABLED" != "true" ]; then
    echo "one password unlocks the disk and the login is not automatic" >&2
    exit 1
fi

# Flatpak off means none at all: a member of the group that depends on it would
# bring it and Flathub along.
if [ "$ARCH_OS_FLATPAK_ENABLED" != "true" ] && has_command flatpak; then
    echo "Flatpak is off and flatpak was installed all the same" >&2
    exit 1
fi

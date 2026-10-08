arch-chroot "$MNT" systemctl is-enabled gdm.service >/dev/null

has_command gnome-software

arch-chroot "$MNT" systemctl --global is-enabled pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null

# Without the module the daemon runs and nothing reaches a .local name.
grep -q 'mdns_minimal' "${MNT}/etc/nsswitch.conf"
[ "$ARCH_OS_FIREWALL_ENABLED" != "true" ] ||
    arch-chroot "$MNT" firewall-offline-cmd --zone=public --query-service=mdns >/dev/null

has_command seahorse

# Automatic login hands the keyring the disk password, which only one password
# makes the account's too.
if [ "$ARCH_OS_DISK_PASSWORD_ENABLED" = "true" ] && grep -qs 'AutomaticLoginEnable=True' "${MNT}/etc/gdm/custom.conf"; then
    echo "the disk has a password of its own and the login is automatic" >&2
    exit 1
fi

# Flatpak off means none at all: a member of the group that depends on it would
# bring it and Flathub along.
if [ "$ARCH_OS_FLATPAK_ENABLED" != "true" ] && has_command flatpak; then
    echo "Flatpak is off and flatpak was installed all the same" >&2
    exit 1
fi

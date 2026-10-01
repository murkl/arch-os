# A desktop nobody can log in to is not a desktop.

arch-chroot "$MNT" systemctl is-enabled gdm.service >/dev/null

# The store is the one that was chosen, and only that one: Bazaar where it takes
# Software's place, otherwise GNOME's own, which the group brings.
if bazaar_wanted; then
    has_command bazaar
    if has_command gnome-software; then
        echo "GNOME Software is installed beside Bazaar" >&2
        exit 1
    fi
else
    has_command gnome-software
fi

# Extension Manager stands in for the Extensions app, which is no longer listed.
if [ "$ARCH_OS_EXTENSION_MANAGER_ENABLED" = "true" ]; then
    has_command extension-manager
    grep -qx 'Hidden=true' "${MNT}/home/${ARCH_OS_USERNAME}/.local/share/applications/org.gnome.Extensions.desktop"
fi

# And sound, which only starts where these sockets are there to be spoken to.
arch-chroot "$MNT" systemctl --global is-enabled pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null

# avahi announces this machine and finds the others; without the module in the
# hosts line nothing can reach any of them by the .local name they answer to,
# and the daemon looks like it is working the whole time.
grep -q 'mdns_minimal' "${MNT}/etc/nsswitch.conf"

# And the firewall lets avahi's answers in on every network, which arrive as
# multicast nothing matches to the question that went out.
[ "$ARCH_OS_FIREWALL_ENABLED" != "true" ] ||
    arch-chroot "$MNT" firewall-offline-cmd --zone=public --query-service=mdns >/dev/null

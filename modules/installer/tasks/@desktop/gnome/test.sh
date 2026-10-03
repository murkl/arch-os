arch-chroot "$MNT" systemctl is-enabled gdm.service >/dev/null

# One store, the one chosen - by the rule task.sh decides with.
if [ "$ARCH_OS_FLATPAK_ENABLED" = "true" ] && [ "$ARCH_OS_BAZAAR_ENABLED" = "true" ]; then
    has_command bazaar
    if has_command gnome-software; then
        echo "GNOME Software is installed beside Bazaar" >&2
        exit 1
    fi
else
    has_command gnome-software
fi

if [ "$ARCH_OS_EXTENSION_MANAGER_ENABLED" = "true" ]; then
    has_command extension-manager
    grep -qx 'Hidden=true' "${MNT}/home/${ARCH_OS_USERNAME}/.local/share/applications/org.gnome.Extensions.desktop"
fi

arch-chroot "$MNT" systemctl --global is-enabled pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null

# Without the module the daemon runs and nothing reaches a .local name.
grep -q 'mdns_minimal' "${MNT}/etc/nsswitch.conf"
[ "$ARCH_OS_FIREWALL_ENABLED" != "true" ] ||
    arch-chroot "$MNT" firewall-offline-cmd --zone=public --query-service=mdns >/dev/null

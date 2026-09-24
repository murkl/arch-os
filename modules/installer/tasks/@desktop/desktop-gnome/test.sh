# A desktop nobody can log in to is not a desktop.

arch-chroot "$MNT" systemctl is-enabled gdm.service >/dev/null

# And sound, which only starts where these sockets are there to be spoken to.
arch-chroot "$MNT" systemctl --global is-enabled pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null

# avahi announces this machine and finds the others; without the module in the
# hosts line nothing can reach any of them by the .local name they answer to,
# and the daemon looks like it is working the whole time.
grep -q 'mdns_minimal' "${MNT}/etc/nsswitch.conf"

# And the firewall lets avahi's answers in, which arrive as multicast nothing
# matches to the question that went out.
[ "$ARCH_OS_FIREWALL_ENABLED" != "true" ] ||
    arch-chroot "$MNT" firewall-offline-cmd --query-service=mdns >/dev/null

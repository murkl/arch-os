# sshd -t would be the stronger check, but it refuses to run without host keys,
# and those are generated at the first boot rather than here.

arch-chroot "$MNT" systemctl is-enabled sshd.service >/dev/null

# And every network lets it in, which is what public stands for.
[ "$ARCH_OS_FIREWALL_ENABLED" != "true" ] ||
    arch-chroot "$MNT" firewall-offline-cmd --zone=public --query-service=ssh >/dev/null

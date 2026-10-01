# Not sshd -t: it needs host keys, which the first boot generates.
arch-chroot "$MNT" systemctl is-enabled sshd.service >/dev/null
[ "$ARCH_OS_FIREWALL_ENABLED" != "true" ] ||
    arch-chroot "$MNT" firewall-offline-cmd --zone=public --query-service=ssh >/dev/null

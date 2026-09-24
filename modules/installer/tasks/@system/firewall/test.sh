# The daemon starts at boot, and the rules it will load are ones it can read.

arch-chroot "$MNT" systemctl is-enabled firewalld.service >/dev/null
arch-chroot "$MNT" firewall-offline-cmd --check-config >/dev/null

# The SSH server opens no port of its own: it relies on the default zone letting
# ssh in, which is firewalld's default rather than anything set here.
[ "$ARCH_OS_SSH_SERVER_ENABLED" != "true" ] ||
    arch-chroot "$MNT" firewall-offline-cmd --query-service=ssh >/dev/null

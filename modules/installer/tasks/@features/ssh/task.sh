# openssh is installed for the client; this lets the server start, configured
# as Arch ships it: no root login with a password, and the account keeps one
# because it has no key yet - see docs/REFERENCE.md.
# https://wiki.archlinux.org/title/OpenSSH#Server_usage
arch-chroot "$MNT" systemctl enable sshd.service

# Reachable on every network, which is what logging in from elsewhere means.
if [ "$ARCH_OS_FIREWALL_ENABLED" = "true" ]; then
    arch-chroot "$MNT" firewall-offline-cmd --zone=public --add-service=ssh
fi

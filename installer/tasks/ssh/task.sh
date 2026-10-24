# sshd as Arch ships it: no root login by password. The account keeps password
# login, having no key yet: docs/REFERENCE.md
# https://wiki.archlinux.org/title/OpenSSH#Server_usage
arch-chroot "$MNT" systemctl enable sshd.service

# Open in public, since a remote login comes from any network.
if [ "$ARCH_OS_FIREWALL_ENABLED" = "true" ]; then
    arch-chroot "$MNT" firewall-offline-cmd --zone=public --add-service=ssh
fi

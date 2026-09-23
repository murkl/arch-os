# firewalld rather than ufw: NetworkManager hands it a zone per connection, and
# libvirt, docker and podman each open their own ports in it. Its default zone
# lets in ssh and DHCPv6 and nothing else; the task that adds a service which
# listens on the network opens that service's port itself.
# https://wiki.archlinux.org/title/Firewalld

packages=(firewalld)

# The window the rules are kept in, packaged apart from the daemon because it
# needs GTK.
[ "$ARCH_OS_DESKTOP" != "none" ] && packages+=(firewall-config)

chroot_pacman_install "${packages[@]}"
arch-chroot "$MNT" systemctl enable firewalld.service

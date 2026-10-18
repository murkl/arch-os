# firewalld, because NetworkManager hands it every connection's zone and libvirt,
# docker and podman open their own ports in it. Which zone lets in what:
# docs/REFERENCE.md#the-firewall
# https://wiki.archlinux.org/title/Firewalld
chroot_pacman_install firewalld
arch-chroot "$MNT" systemctl enable firewalld.service

# public, where every unmarked network lands, lets ssh in as shipped; the SSH
# server task opens it again itself.
arch-chroot "$MNT" firewall-offline-cmd --zone=public --remove-service-from-zone=ssh

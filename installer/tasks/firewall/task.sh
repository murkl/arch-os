# NetworkManager hands firewalld every connection's zone, and libvirt and
# podman open their ports in it. Docker passes it, see the containers task.
# Zones: docs/REFERENCE.md#firewall
# https://wiki.archlinux.org/title/Firewalld
chroot_pacman_install firewalld
arch-chroot "$MNT" systemctl enable firewalld.service

# public, the zone of every unmarked network, ships with ssh open. The ssh task
# opens it again.
arch-chroot "$MNT" firewall-offline-cmd --zone=public --remove-service-from-zone=ssh

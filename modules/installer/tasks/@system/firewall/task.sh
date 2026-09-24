# firewalld rather than ufw: NetworkManager hands it the zone of every
# connection, and libvirt, docker and podman each open their own ports in it.
# Two zones carry the whole policy, and the task that makes something listen
# opens its port in the zone it belongs in. Which zone lets in what and why:
# docs/REFERENCE.md
# https://wiki.archlinux.org/title/Firewalld

chroot_pacman_install firewalld
arch-chroot "$MNT" systemctl enable firewalld.service

# public is the default zone, where every network lands that nobody has marked
# as home - a café's wifi as much as the one at home. firewalld lets ssh in
# there whether anything answers or not; the SSH server opens it again itself.
# --remove-service is the lokkit spelling, which refuses a zone.
arch-chroot "$MNT" firewall-offline-cmd --zone=public --remove-service-from-zone=ssh

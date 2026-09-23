# The daemon starts at boot, and the rules it will load are ones it can read.

arch-chroot "$MNT" systemctl is-enabled firewalld.service >/dev/null
arch-chroot "$MNT" firewall-offline-cmd --check-config >/dev/null

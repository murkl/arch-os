# A desktop nobody can log in to is not a desktop.
debugging && return 0

arch-chroot "$MNT" systemctl is-enabled gdm.service >/dev/null

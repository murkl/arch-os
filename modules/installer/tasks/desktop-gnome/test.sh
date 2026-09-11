# A desktop nobody can log in to is not a desktop.
arch-chroot "$MNT" systemctl is-enabled gdm.service >/dev/null

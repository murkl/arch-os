# A desktop nobody can log in to is not a desktop.
debugging && return 0

arch-chroot "$MNT" systemctl is-enabled gdm.service >/dev/null

# The theme override at the end of the task needs this, and the gnome group
# never pulls it in - a machine that has it only as a recommendation fails
# there silently unless this is checked directly.
arch-chroot "$MNT" flatpak --version >/dev/null

# A desktop nobody can log in to is not a desktop.

arch-chroot "$MNT" systemctl is-enabled gdm.service >/dev/null

# The theme override at the end of the task needs this, and the gnome group
# never pulls it in - a machine that has it only as a recommendation fails
# there silently unless this is checked directly.
arch-chroot "$MNT" flatpak --version >/dev/null

# avahi announces this machine and finds the others; without the module in the
# hosts line nothing can reach any of them by the .local name they answer to,
# and the daemon looks like it is working the whole time.
grep -q 'mdns_minimal' "${MNT}/etc/nsswitch.conf"

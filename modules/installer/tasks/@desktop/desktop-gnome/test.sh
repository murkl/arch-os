# A desktop nobody can log in to is not a desktop.

arch-chroot "$MNT" systemctl is-enabled gdm.service >/dev/null

# avahi announces this machine and finds the others; without the module in the
# hosts line nothing can reach any of them by the .local name they answer to,
# and the daemon looks like it is working the whole time.
grep -q 'mdns_minimal' "${MNT}/etc/nsswitch.conf"

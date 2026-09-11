# The timers are the whole point: the packages are only what they run.
for timer in reflector.timer paccache.timer pkgfile-update.timer; do
    arch-chroot "$MNT" systemctl is-enabled "$timer" >/dev/null
done
[ -f "${MNT}/etc/xdg/reflector/reflector.conf" ]

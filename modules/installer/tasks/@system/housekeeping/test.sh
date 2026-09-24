# The timers are the whole point: the packages are only what they run.

for timer in reflector.timer paccache.timer; do
    arch-chroot "$MNT" systemctl is-enabled "$timer" >/dev/null
done

# And the file the reflector timer runs with, read by reflector's own parser: a
# line it cannot split into arguments looks fine in the file and fails the
# service every week, which nobody sees until the mirrors have gone stale.
arch-chroot "$MNT" python3 -c 'import Reflector; Reflector.parse_args(["@/etc/xdg/reflector/reflector.conf"])'

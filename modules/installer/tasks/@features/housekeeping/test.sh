for timer in reflector.timer paccache.timer; do
    arch-chroot "$MNT" systemctl is-enabled "$timer" >/dev/null
done

# Read by reflector's own parser: a line it cannot split fails the timer weekly.
arch-chroot "$MNT" python3 -c 'import Reflector; Reflector.parse_args(["@/etc/xdg/reflector/reflector.conf"])'

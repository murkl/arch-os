chroot_pacman_install pacman-contrib reflector smartmontools

# Overwritten in place, since reflector.service names this path in its command
# line and its sandbox. Quoted, or United States is two arguments.
render "$(where)/reflector.conf" >"${MNT}/etc/xdg/reflector/reflector.conf"
country="$(mirror_country)"
if [ -n "$country" ]; then
    printf -- '--country "%s"\n' "$country" >>"${MNT}/etc/xdg/reflector/reflector.conf"
fi

arch-chroot "$MNT" systemctl enable reflector.timer
arch-chroot "$MNT" systemctl enable paccache.timer
arch-chroot "$MNT" systemctl enable smartd # skips itself in a guest

# Skipped offline instead of failed.
mkdir -p "${MNT}/etc/systemd/system/reflector.service.d"
render "$(where)/online.conf" >"${MNT}/etc/systemd/system/reflector.service.d/online.conf"

chroot_pacman_install pacman-contrib reflector smartmontools

# An edit: reflector.service names this exact path in its command line and its
# sandbox. The country quoted, or United States is two arguments.
render "$(where)/reflector.conf" >"${MNT}/etc/xdg/reflector/reflector.conf"
country="$(mirror_country)"
if [ -n "$country" ]; then
    printf -- '--country "%s"\n' "$country" >>"${MNT}/etc/xdg/reflector/reflector.conf"
fi

arch-chroot "$MNT" systemctl enable reflector.timer # rank mirrors weekly
arch-chroot "$MNT" systemctl enable paccache.timer  # trim the package cache
arch-chroot "$MNT" systemctl enable smartd          # watch disk health, down by itself in a guest

# Offline the ranking is skipped rather than failed.
mkdir -p "${MNT}/etc/systemd/system/reflector.service.d"
render "$(where)/online.conf" >"${MNT}/etc/systemd/system/reflector.service.d/online.conf"

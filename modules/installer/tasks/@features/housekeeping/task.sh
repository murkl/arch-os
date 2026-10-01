chroot_pacman_install pacman-contrib reflector smartmontools

# An edit: reflector.service names this exact path in its command line and its
# sandbox. The country quoted, or United States is two arguments.
render "$(where)/reflector.conf" >"${MNT}/etc/xdg/reflector/reflector.conf"
if [ -n "$ARCH_OS_REFLECTOR_COUNTRY" ]; then
    printf -- '--country "%s"\n' "$ARCH_OS_REFLECTOR_COUNTRY" >>"${MNT}/etc/xdg/reflector/reflector.conf"
fi

arch-chroot "$MNT" systemctl enable reflector.timer # rank mirrors weekly
arch-chroot "$MNT" systemctl enable paccache.timer  # trim the package cache
arch-chroot "$MNT" systemctl enable smartd          # watch disk health

# A guest's kernel refuses every affinity irqbalance sets and logs each refusal.
# smartd stays: its unit stays down in a guest by itself.
if [ "$ARCH_OS_VIRTUAL_MACHINE" = "false" ]; then
    chroot_pacman_install irqbalance
    arch-chroot "$MNT" systemctl enable irqbalance.service
fi

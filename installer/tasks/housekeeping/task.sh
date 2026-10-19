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
arch-chroot "$MNT" systemctl enable smartd          # watch disk health

# The weekly trim leaves out every kernel a snapshot has installed: a rollback
# past a kernel update needs that package to rebuild the boot files from.
mkdir -p "${MNT}/usr/local/lib/arch-os" "${MNT}/etc/systemd/system/paccache.service.d"
render "$(where)/paccache.sh" >"${MNT}/usr/local/lib/arch-os/paccache.sh"
chmod 755 "${MNT}/usr/local/lib/arch-os/paccache.sh"
render "$(where)/paccache.conf" >"${MNT}/etc/systemd/system/paccache.service.d/snapshots.conf"

# Offline the ranking is skipped rather than failed.
mkdir -p "${MNT}/etc/systemd/system/reflector.service.d"
render "$(where)/online.conf" >"${MNT}/etc/systemd/system/reflector.service.d/online.conf"

# A guest's kernel refuses every affinity irqbalance sets and logs each refusal.
# smartd stays: its unit stays down in a guest by itself.
if [ "$ARCH_OS_VIRTUAL_MACHINE" = "false" ]; then
    chroot_pacman_install irqbalance
    arch-chroot "$MNT" systemctl enable irqbalance.service
fi

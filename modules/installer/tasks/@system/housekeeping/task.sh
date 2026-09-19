# Timers that keep the system tidy without anybody remembering to.

simulating && return 0

chroot_pacman_install pacman-contrib reflector pkgfile smartmontools

# reflector.service names this exact path on its command line, so a drop-in
# could only override it by restating the whole command - which would then be
# ours to keep in step with the unit.
{
    echo "# Written by the Arch OS Installer, read by reflector.service."
    echo "--save /etc/pacman.d/mirrorlist"
    [ -n "$ARCH_OS_REFLECTOR_COUNTRY" ] && echo "--country ${ARCH_OS_REFLECTOR_COUNTRY}"
    echo "--protocol https"
    echo "--age 12"
    echo "--latest 10"
    echo "--sort rate"
} >"${MNT}/etc/xdg/reflector/reflector.conf"

arch-chroot "$MNT" systemctl enable reflector.timer      # rank mirrors weekly
arch-chroot "$MNT" systemctl enable paccache.timer       # trim the package cache
arch-chroot "$MNT" systemctl enable pkgfile-update.timer # "command not found" knows what to suggest
arch-chroot "$MNT" systemctl enable smartd               # watch disk health

# Interrupts belong to the hardware, and a guest has none of its own: inside a
# virtual machine the kernel refuses every affinity irqbalance tries to set, and
# it writes that refusal into the log once per interrupt at every boot. So it is
# installed where there is something for it to spread. smartd stays either way -
# it finds nothing to watch in a guest and says nothing about it.
if [ "$(systemd-detect-virt || true)" = "none" ]; then
    chroot_pacman_install irqbalance
    arch-chroot "$MNT" systemctl enable irqbalance.service
fi

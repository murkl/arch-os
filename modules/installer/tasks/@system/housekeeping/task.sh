# Timers that keep the system tidy without anybody remembering to.

chroot_pacman_install pacman-contrib reflector smartmontools

# reflector.service names this exact path on its command line and in its
# sandbox, so a drop-in could only move it by restating both - which would then
# be ours to keep in step with the unit, and leave the file the Wiki points at
# read by nothing. The country is a line of its own or none at all, and quoted:
# reflector splits every line the way a shell would, and United States
# unquoted is two arguments it refuses to start with.
render "$(where)/reflector.conf" >"${MNT}/etc/xdg/reflector/reflector.conf"
if [ -n "$ARCH_OS_REFLECTOR_COUNTRY" ]; then
    printf -- '--country "%s"\n' "$ARCH_OS_REFLECTOR_COUNTRY" >>"${MNT}/etc/xdg/reflector/reflector.conf"
fi

arch-chroot "$MNT" systemctl enable reflector.timer # rank mirrors weekly
arch-chroot "$MNT" systemctl enable paccache.timer  # trim the package cache
arch-chroot "$MNT" systemctl enable smartd          # watch disk health

# Interrupts belong to the hardware, and a guest has none of its own: inside a
# virtual machine the kernel refuses every affinity irqbalance tries to set, and
# it writes that refusal into the log once per interrupt at every boot. So it is
# installed where there is something for it to spread. smartd stays either way:
# its own unit declares ConditionVirtualization=no and stays down in a guest.
if [ "$ARCH_OS_VIRTUAL_MACHINE" = "false" ]; then
    chroot_pacman_install irqbalance
    arch-chroot "$MNT" systemctl enable irqbalance.service
fi

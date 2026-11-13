arch-chroot "$MNT" systemctl is-enabled cups.socket >/dev/null
arch-chroot "$MNT" systemctl is-enabled fwupd-refresh.timer >/dev/null

# The plugin GStreamer decodes on the GPU with.
[ -f "${MNT}/usr/lib/gstreamer-1.0/libgstva.so" ]

groups="$(arch-chroot "$MNT" id -nG "$ARCH_OS_USERNAME")"
[[ " ${groups} " == *" gamemode "* ]]

# The gnome task masked cups' entry before cups arrived.
found="$(app_listed cups.desktop)"
[ "$found" = false ]

packages=(reflector smartmontools)
# notify-send, for a disk warning on the desktop.
[ "$ARCH_OS_DESKTOP" != "none" ] && packages+=(libnotify)
chroot_pacman_install "${packages[@]}"

# Overwritten in place, since reflector.service names this path in its command
# line and its sandbox. Quoted, or United States is two arguments.
render "$(where)/reflector.conf" | write_file "${MNT}/etc/xdg/reflector/reflector.conf"
country="$(mirror_country)"
if [ -n "$country" ]; then
    printf -- '--country "%s"\n' "$country" | write_file -a "${MNT}/etc/xdg/reflector/reflector.conf"
fi

run arch-chroot "$MNT" systemctl enable reflector.timer
run arch-chroot "$MNT" systemctl enable smartd # skips itself in a guest

# A failing disk reaches every terminal and session, not just the journal. A
# single quote in the heading's translation would end the script's string.
if [[ "$DISK_ALERT" == *"'"* ]]; then
    echo "the disk warning's heading holds a single quote: ${DISK_ALERT}" >&2
    exit 1
fi
run mkdir -p "${MNT}/usr/local/lib/arch-os"
render "$(where)/smartd-notify" TITLE="$DISK_ALERT" | write_file "${MNT}/usr/local/lib/arch-os/smartd-notify"
run chmod 755 "${MNT}/usr/local/lib/arch-os/smartd-notify"
render "$(where)/smartd.conf" | write_file "${MNT}/etc/smartd.conf"

# Skipped offline instead of failed.
run mkdir -p "${MNT}/etc/systemd/system/reflector.service.d"
render "$(where)/online.conf" | write_file "${MNT}/etc/systemd/system/reflector.service.d/online.conf"

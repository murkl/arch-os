grep -qx "$ARCH_OS_HOSTNAME" "${MNT}/etc/hostname"

arch-chroot "$MNT" systemctl is-enabled NetworkManager >/dev/null

# NetworkManager ignores a profile that others can read.
for profile in /var/lib/iwd/*.psk /var/lib/iwd/*.open; do
    [ -f "$profile" ] || continue
    name="$(basename "$profile")"
    [ "$(stat -c %a "${MNT}/etc/NetworkManager/system-connections/${name%.*}.nmconnection")" = 600 ]
done

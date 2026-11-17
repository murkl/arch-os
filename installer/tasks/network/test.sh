grep -qx "$ARCH_OS_HOSTNAME" "${MNT}/etc/hostname"

arch-chroot "$MNT" systemctl is-enabled NetworkManager >/dev/null

# NetworkManager ignores a profile that others can read.
for profile in /var/lib/iwd/*.psk /var/lib/iwd/*.open; do
    [ -f "$profile" ] || continue
    name="$(basename "$profile")"
    keyfile="${MNT}/etc/NetworkManager/system-connections/${name%.*}.nmconnection"
    [ "$(stat -c %a "$keyfile")" = 600 ]
    # Both store the passphrase with GLib's escapes, so it is carried verbatim.
    passphrase="$(sed -n 's/^Passphrase=//p' "$profile")"
    [ -z "$passphrase" ] || grep -qxF "psk=${passphrase}" "$keyfile"
done

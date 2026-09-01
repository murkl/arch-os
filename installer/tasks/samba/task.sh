# File sharing the rest of the network can see, and the two discovery services
# that make this machine appear in it.

simulating && return 0

mkdir -p "${MNT}/etc/samba"
cp "$(where)/smb.conf" "${MNT}/etc/samba/smb.conf"

if [ "$ARCH_OS_SAMBA_SHARE_ENABLED" = "true" ]; then
    cat "$(where)/smb-shares.conf" >>"${MNT}/etc/samba/smb.conf"
fi

# Samba refuses to start on a broken file, so it is checked first.
arch-chroot "$MNT" testparm -s /etc/samba/smb.conf

if [ "$ARCH_OS_SAMBA_SHARE_ENABLED" = "true" ]; then
    arch-chroot "$MNT" mkdir -p /srv/samba/public
    arch-chroot "$MNT" chmod 777 /srv/samba/public
    arch-chroot "$MNT" chown -R nobody:users /srv/samba/public

    # Samba keeps its own password database, set to the same password.
    printf '%s\n%s\n' "$ARCH_OS_PASSWORD" "$ARCH_OS_PASSWORD" |
        arch-chroot "$MNT" smbpasswd -s -a "$ARCH_OS_USERNAME"
fi

# Windows and macOS both find the machine faster over IPv4 only, and both
# services try IPv6 first.
# https://wiki.archlinux.org/title/Samba#Windows_1709_or_up_does_not_discover_the_samba_server_in_Network_view
grep -q -- '-4' "${MNT}/etc/conf.d/wsdd" || sed -i 's/WSDD_PARAMS="/WSDD_PARAMS="-4 /' "${MNT}/etc/conf.d/wsdd"
sed -i -E 's/^#?\s*use-ipv6=.*/use-ipv6=no/' "${MNT}/etc/avahi/avahi-daemon.conf"

arch-chroot "$MNT" systemctl enable smb.service
arch-chroot "$MNT" systemctl enable wsdd.service

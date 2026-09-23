# File sharing the rest of the network can see, and the discovery wsdd gives it
# so that Windows finds this machine at all.
# https://wiki.archlinux.org/title/Samba

data="$(where)"

chroot_pacman_install samba wsdd

mkdir -p "${MNT}/etc/samba"
render "${data}/smb.conf" USERNAME="$ARCH_OS_USERNAME" >"${MNT}/etc/samba/smb.conf"

# Samba refuses to start on a broken file, so it is checked first.
arch-chroot "$MNT" testparm -s /etc/samba/smb.conf

arch-chroot "$MNT" mkdir -p /srv/samba/public
arch-chroot "$MNT" chmod 777 /srv/samba/public
arch-chroot "$MNT" chown -R nobody:users /srv/samba/public

# Samba keeps its own password database, set to the same password.
printf '%s\n%s\n' "$ARCH_OS_PASSWORD" "$ARCH_OS_PASSWORD" |
    arch-chroot "$MNT" smbpasswd -s -a "$ARCH_OS_USERNAME"

# Windows finds the machine faster over IPv4 alone, and wsdd tries IPv6 first.
# A drop-in is read after the unit's own environment file, so it wins - and
# what it replaces is `--workgroup WORKGROUP`, which /etc/conf.d/wsdd sets and
# which wsdd would pick as its own default anyway. Named here because that is
# the only reason dropping it is safe.
# https://wiki.archlinux.org/title/Samba#Windows_1709_or_up_does_not_discover_the_samba_server_in_Network_view
mkdir -p "${MNT}/etc/systemd/system/wsdd.service.d"
render "${data}/ipv4.conf" >"${MNT}/etc/systemd/system/wsdd.service.d/ipv4.conf"

arch-chroot "$MNT" systemctl enable smb.service
arch-chroot "$MNT" systemctl enable wsdd.service

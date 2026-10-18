# File sharing, and the discovery wsdd gives it so Windows finds the machine.
# https://wiki.archlinux.org/title/Samba

data="$(where)"
chroot_pacman_install samba wsdd

mkdir -p "${MNT}/etc/samba"
render "${data}/smb.conf" USERNAME="$ARCH_OS_USERNAME" >"${MNT}/etc/samba/smb.conf"
arch-chroot "$MNT" testparm -s /etc/samba/smb.conf

arch-chroot "$MNT" mkdir -p /srv/samba/public
arch-chroot "$MNT" chmod 777 /srv/samba/public
arch-chroot "$MNT" chown -R nobody:users /srv/samba/public

# Samba keeps its own password database, set to the same password.
printf '%s\n%s\n' "$ARCH_OS_PASSWORD" "$ARCH_OS_PASSWORD" |
    arch-chroot "$MNT" smbpasswd -s -a "$ARCH_OS_USERNAME"

# IPv4 alone, which Windows finds faster. The drop-in replaces the unit's
# `--workgroup WORKGROUP`, which is wsdd's own default anyway.
# https://wiki.archlinux.org/title/Samba#Windows_1709_or_up_does_not_discover_the_samba_server_in_Network_view
mkdir -p "${MNT}/etc/systemd/system/wsdd.service.d"
render "${data}/ipv4.conf" >"${MNT}/etc/systemd/system/wsdd.service.d/ipv4.conf"

arch-chroot "$MNT" systemctl enable smb.service
arch-chroot "$MNT" systemctl enable wsdd.service

# On networks marked as home only: on a café's wifi a share is a password
# anybody there can try.
if [ "$ARCH_OS_FIREWALL_ENABLED" = "true" ]; then
    arch-chroot "$MNT" firewall-offline-cmd --zone=home --add-service=samba --add-service=ws-discovery-host
fi

# wsdd, so Windows finds the machine.
# https://wiki.archlinux.org/title/Samba

data="$(where)"
chroot_pacman_install samba wsdd

mkdir -p "${MNT}/etc/samba"
render "${data}/smb.conf" USERNAME="$ARCH_OS_USERNAME" >"${MNT}/etc/samba/smb.conf"
arch-chroot "$MNT" testparm -s /etc/samba/smb.conf

arch-chroot "$MNT" mkdir -p /srv/samba/public
arch-chroot "$MNT" chmod 755 /srv/samba/public
arch-chroot "$MNT" chown "${ARCH_OS_USERNAME}:${ARCH_OS_USERNAME}" /srv/samba/public

# Samba keeps its own password database, set to the account's password.
printf '%s\n%s\n' "$ARCH_OS_PASSWORD" "$ARCH_OS_PASSWORD" |
    arch-chroot "$MNT" smbpasswd -s -a "$ARCH_OS_USERNAME"

# IPv4 only, which Windows finds faster. Appended to the unit's environment
# file, whose last assignment wins over the shipped `--workgroup WORKGROUP`,
# wsdd's default anyway.
# https://wiki.archlinux.org/title/Samba#Windows_1709_or_up_does_not_discover_the_samba_server_in_Network_view
render "${data}/wsdd" >>"${MNT}/etc/conf.d/wsdd"

arch-chroot "$MNT" systemctl enable smb.service
arch-chroot "$MNT" systemctl enable wsdd.service

# home only: on public Wi-Fi anybody there can guess the share's password.
if [ "$ARCH_OS_FIREWALL_ENABLED" = "true" ]; then
    arch-chroot "$MNT" firewall-offline-cmd --zone=home --add-service=samba --add-service=ws-discovery-host
fi

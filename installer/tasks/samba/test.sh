arch-chroot "$MNT" testparm -s >/dev/null 2>&1
arch-chroot "$MNT" systemctl is-enabled smb.service >/dev/null

# testparm prints a default like a set value, so the value is compared.
[ "$(arch-chroot "$MNT" testparm -s --parameter-name='mdns name' 2>/dev/null)" = mdns ]

# Neither guests nor other accounts write: anybody could fill the share.
[ "$(arch-chroot "$MNT" testparm -s --section-name=public --parameter-name='read only' 2>/dev/null)" = Yes ]
[ "$(arch-chroot "$MNT" stat -c '%U %a' /srv/samba/public)" = "${ARCH_OS_USERNAME} 755" ]

if [ "$ARCH_OS_FIREWALL_ENABLED" = "true" ]; then
    arch-chroot "$MNT" firewall-offline-cmd --zone=home --query-service=samba >/dev/null
    arch-chroot "$MNT" firewall-offline-cmd --zone=home --query-service=ws-discovery-host >/dev/null
    if arch-chroot "$MNT" firewall-offline-cmd --zone=public --query-service=samba >/dev/null; then
        echo "samba open in public, not only in home" >&2
        exit 1
    fi
fi

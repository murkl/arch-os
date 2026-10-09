arch-chroot "$MNT" testparm -s >/dev/null 2>&1
arch-chroot "$MNT" systemctl is-enabled smb.service >/dev/null

# Asked of samba, which shows a key it never read the same as one it did.
[ "$(arch-chroot "$MNT" testparm -s --parameter-name='mdns name' 2>/dev/null)" = mdns ]

# A guest who may write is a folder anybody on the network can fill.
[ "$(arch-chroot "$MNT" testparm -s --section-name=public --parameter-name='read only' 2>/dev/null)" = Yes ]

if [ "$ARCH_OS_FIREWALL_ENABLED" = "true" ]; then
    arch-chroot "$MNT" firewall-offline-cmd --zone=home --query-service=samba >/dev/null
    arch-chroot "$MNT" firewall-offline-cmd --zone=home --query-service=ws-discovery-host >/dev/null
    if arch-chroot "$MNT" firewall-offline-cmd --zone=public --query-service=samba >/dev/null; then
        echo "the share is open on every network, not only on home ones" >&2
        exit 1
    fi
fi

# The share is valid to samba itself, and something is there to announce it.

arch-chroot "$MNT" testparm -s >/dev/null 2>&1
arch-chroot "$MNT" systemctl is-enabled smb.service >/dev/null

# Asked of samba rather than of the file: what a file manager on the network
# shows is the value samba resolved, and a key it never read looks the same in
# the file as one it did.
[ "$(arch-chroot "$MNT" testparm -s --parameter-name='mdns name' 2>/dev/null)" = mdns ]

# And the public share takes writes only from the account: a guest who may write
# is a folder anybody on the same network can fill.
[ "$(arch-chroot "$MNT" testparm -s --section-name=public --parameter-name='read only' 2>/dev/null)" = Yes ]

# The share and the discovery that makes Windows list this machine, both let in
# at home - and the share nowhere else.
if [ "$ARCH_OS_FIREWALL_ENABLED" = "true" ]; then
    arch-chroot "$MNT" firewall-offline-cmd --zone=home --query-service=samba >/dev/null
    arch-chroot "$MNT" firewall-offline-cmd --zone=home --query-service=ws-discovery-host >/dev/null
    if arch-chroot "$MNT" firewall-offline-cmd --zone=public --query-service=samba >/dev/null; then
        echo "the share is open on every network, not only on home ones" >&2
        exit 1
    fi
fi

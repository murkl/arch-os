arch-chroot "$MNT" systemctl is-enabled firewalld.service >/dev/null
arch-chroot "$MNT" firewall-offline-cmd --check-config >/dev/null

[ "$(arch-chroot "$MNT" firewall-offline-cmd --get-default-zone)" = public ]
if arch-chroot "$MNT" firewall-offline-cmd --zone=public --query-service=ssh >/dev/null; then
    echo "ssh open in public with no server yet" >&2
    exit 1
fi

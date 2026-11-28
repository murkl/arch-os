arch-chroot "$MNT" systemctl is-enabled firewalld.service >/dev/null
arch-chroot "$MNT" firewall-offline-cmd --check-config >/dev/null

[ "$(arch-chroot "$MNT" firewall-offline-cmd --get-default-zone)" = public ]
if arch-chroot "$MNT" firewall-offline-cmd --zone=public --query-service=ssh >/dev/null; then
    echo "ssh open in public with no server yet" >&2
    exit 1
fi

for protocol in tcp udp; do
    arch-chroot "$MNT" firewall-offline-cmd --zone=home --query-port="1025-65535/${protocol}" >/dev/null
    if arch-chroot "$MNT" firewall-offline-cmd --zone=public --query-port="1025-65535/${protocol}" >/dev/null; then
        echo "1025-65535/${protocol} open in public, not only in home" >&2
        exit 1
    fi
done

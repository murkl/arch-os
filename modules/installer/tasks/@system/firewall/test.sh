# The daemon starts at boot, and the rules it will load are ones it can read.

arch-chroot "$MNT" systemctl is-enabled firewalld.service >/dev/null
arch-chroot "$MNT" firewall-offline-cmd --check-config >/dev/null

# Every network nobody has marked lands in public, and public lets in nothing
# that nothing here answers yet.
[ "$(arch-chroot "$MNT" firewall-offline-cmd --get-default-zone)" = public ]
if arch-chroot "$MNT" firewall-offline-cmd --zone=public --query-service=ssh >/dev/null; then
    echo "public lets ssh in, and nothing listens there yet" >&2
    exit 1
fi

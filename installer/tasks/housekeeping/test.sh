for timer in reflector.timer paccache.timer; do
    arch-chroot "$MNT" systemctl is-enabled "$timer" >/dev/null
done

# The trim runs the script that keeps the snapshots' kernels, as systemd reads it.
[ -x "${MNT}/usr/local/lib/arch-os/paccache.sh" ]
[ -z "$(unit_complaints paccache.service)" ]
grep -qxF "ExecStart=/usr/local/lib/arch-os/paccache.sh /.snapshots \$PACCACHE_ARGS" \
    "${MNT}/etc/systemd/system/paccache.service.d/snapshots.conf"

# Skipped offline and run online: the condition answers what ExecCondition
# reads as skip without a network, and yes with one.
[ -z "$(unit_complaints reflector.service)" ]
read -ra condition <<<"$(sed -n 's/^ExecCondition=//p' "${MNT}/etc/systemd/system/reflector.service.d/online.conf")"
status=0
unshare --net arch-chroot "$MNT" "${condition[@]}" || status=$?
[ "$status" -ge 1 ] && [ "$status" -le 254 ]
arch-chroot "$MNT" "${condition[@]}"

# Read by reflector's own parser: a line it cannot split fails the timer weekly.
arch-chroot "$MNT" python3 -c 'import Reflector; Reflector.parse_args(["@/etc/xdg/reflector/reflector.conf"])'

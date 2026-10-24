for timer in reflector.timer paccache.timer; do
    arch-chroot "$MNT" systemctl is-enabled "$timer" >/dev/null
done

# smartd's own parser. 17 means no disk with SMART, as in a virtual machine.
arch-chroot "$MNT" smartd -c /etc/smartd.conf -q showtests >/dev/null 2>&1 || allow 17
# The notifier runs to its end. The chroot has no session to reach.
arch-chroot "$MNT" env SMARTD_DEVICE=/dev/test SMARTD_MESSAGE=test /usr/local/lib/arch-os/smartd-notify >/dev/null 2>&1

# Without a network the condition exits 1 to 254, a skip for ExecCondition, and
# 0 with one.
[ -z "$(unit_complaints reflector.service)" ]
read -ra condition <<<"$(sed -n 's/^ExecCondition=//p' "${MNT}/etc/systemd/system/reflector.service.d/online.conf")"
status=0
unshare --net arch-chroot "$MNT" "${condition[@]}" || status=$?
[ "$status" -ge 1 ] && [ "$status" -le 254 ]
arch-chroot "$MNT" "${condition[@]}"

# reflector's own parser: a line it cannot split fails the timer every week.
arch-chroot "$MNT" python3 -c 'import Reflector; Reflector.parse_args(["@/etc/xdg/reflector/reflector.conf"])'

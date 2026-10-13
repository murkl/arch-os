grep -qx "$ARCH_OS_HOSTNAME" "${MNT}/etc/hostname"
grep -qx "LANG=${ARCH_OS_LOCALE_LANG}.UTF-8" "${MNT}/etc/locale.conf"
[ -f "${MNT}/etc/localtime" ]
sysctl_keys_exist "${MNT}/etc/sysctl.d/99-vm-zram-parameters.conf"
arch-chroot "$MNT" systemctl is-enabled NetworkManager >/dev/null

# Every wireless network the live system joined, readable by root alone, which
# NetworkManager insists on.
for profile in /var/lib/iwd/*.psk /var/lib/iwd/*.open; do
    [ -f "$profile" ] || continue
    name="$(basename "$profile")"
    [ "$(stat -c %a "${MNT}/etc/NetworkManager/system-connections/${name%.*}.nmconnection")" = 600 ]
done
arch-chroot "$MNT" systemctl is-enabled btrfs-scrub@-.timer >/dev/null

# Skipped offline and run online: the condition answers what ExecCondition
# reads as skip without a network, and yes with one.
[ -z "$(systemd-analyze verify --root="$MNT" archlinux-keyring-wkd-sync.service 2>&1)" ]
read -ra condition <<<"$(sed -n 's/^ExecCondition=//p' "${MNT}/etc/systemd/system/archlinux-keyring-wkd-sync.service.d/online.conf")"
status=0
unshare --net arch-chroot "$MNT" "${condition[@]}" || status=$?
[ "$status" -ge 1 ] && [ "$status" -le 254 ]
arch-chroot "$MNT" "${condition[@]}"

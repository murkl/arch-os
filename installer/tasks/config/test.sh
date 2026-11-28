grep -qx "LANG=${ARCH_OS_LOCALE_LANG}.UTF-8" "${MNT}/etc/locale.conf"
# Inside the new system: from outside, the absolute link resolves into the live
# system.
arch-chroot "$MNT" test -f /etc/localtime
# Read the way set-wireless-regdom reads it: a listed country or none.
if [ -f "${MNT}/etc/conf.d/wireless-regdom" ]; then
    regdom="$(bash -c '. "$1" && echo "${WIRELESS_REGDOM:-}"' _ "${MNT}/etc/conf.d/wireless-regdom")"
    [ -z "$regdom" ] || grep -qxF "#WIRELESS_REGDOM=\"${regdom}\"" "${MNT}/etc/conf.d/wireless-regdom"
fi
sysctl_keys_exist "${MNT}/etc/sysctl.d/99-vm-zram-parameters.conf"
arch-chroot "$MNT" systemctl is-enabled btrfs-scrub@-.timer >/dev/null
arch-chroot "$MNT" systemctl is-enabled paccache.timer >/dev/null
arch-chroot "$MNT" systemctl is-enabled systemd-pstore.service >/dev/null

# Without a network the condition exits 1 to 254, a skip for ExecCondition, and
# 0 with one.
[ -z "$(unit_complaints archlinux-keyring-wkd-sync.service)" ]
read -ra condition <<<"$(sed -n 's/^ExecCondition=//p' "${MNT}/etc/systemd/system/archlinux-keyring-wkd-sync.service.d/online.conf")"
status=0
unshare --net arch-chroot "$MNT" "${condition[@]}" || status=$?
[ "$status" -ge 1 ] && [ "$status" -le 254 ]
arch-chroot "$MNT" "${condition[@]}"

grep -qx "LANG=${ARCH_OS_LOCALE_LANG}.UTF-8" "${MNT}/etc/locale.conf"
[ -f "${MNT}/etc/localtime" ]
sysctl_keys_exist "${MNT}/etc/sysctl.d/99-vm-zram-parameters.conf"
arch-chroot "$MNT" systemctl is-enabled btrfs-scrub@-.timer >/dev/null
arch-chroot "$MNT" systemctl is-enabled systemd-pstore.service >/dev/null

# Skipped offline and run online: the condition answers what ExecCondition
# reads as skip without a network, and yes with one.
[ -z "$(unit_complaints archlinux-keyring-wkd-sync.service)" ]
read -ra condition <<<"$(sed -n 's/^ExecCondition=//p' "${MNT}/etc/systemd/system/archlinux-keyring-wkd-sync.service.d/online.conf")"
status=0
unshare --net arch-chroot "$MNT" "${condition[@]}" || status=$?
[ "$status" -ge 1 ] && [ "$status" -le 254 ]
arch-chroot "$MNT" "${condition[@]}"

# Real hardware only, see pacstrap.
if [ "$ARCH_OS_VIRTUAL_MACHINE" = "false" ]; then
    arch-chroot "$MNT" systemctl is-enabled irqbalance.service >/dev/null
fi

# The desktop reads the entry, and the script restarts into an entry the loader
# lists: systemctl refuses an unknown one only after the question was answered.
arch-chroot "$MNT" desktop-file-validate /usr/local/share/applications/arch-os-recovery.desktop
bash -n "${MNT}/usr/local/bin/arch-os-recovery"
[ -x "${MNT}/usr/local/bin/arch-os-recovery" ]

entry="$(basename "$RECOVERY_EFI")"
grep -qF -- "--boot-loader-entry=\"${entry}\"" "${MNT}/usr/local/bin/arch-os-recovery"
entries="$(arch-chroot "$MNT" bootctl --esp-path=/boot list --json=short)"
grep -qF "\"id\":\"${entry}\"" <<<"$entries"

# udev passes over a rule it cannot read without a word.
uuid="$(blkid -p -s UUID -o value "$(recovery_partition "$ARCH_OS_DISK")")"
[ -n "$uuid" ]
grep -qF "\"${uuid}\"" "${MNT}/etc/udev/rules.d/90-arch-os-recovery.rules"
udevadm verify --resolve-names=never --no-style --no-summary "${MNT}/etc/udev/rules.d/90-arch-os-recovery.rules"

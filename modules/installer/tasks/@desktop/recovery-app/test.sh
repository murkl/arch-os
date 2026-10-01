# The desktop reads the entry, and the script restarts into an entry the loader
# lists: systemctl refuses an unknown one only after the question was answered.
arch-chroot "$MNT" desktop-file-validate /usr/local/share/applications/arch-os-recovery.desktop
bash -n "${MNT}/usr/local/bin/arch-os-recovery"
[ -x "${MNT}/usr/local/bin/arch-os-recovery" ]

entry="$(basename "$RECOVERY_EFI")"
grep -qF -- "--boot-loader-entry=\"${entry}\"" "${MNT}/usr/local/bin/arch-os-recovery"
entries="$(arch-chroot "$MNT" bootctl --esp-path=/boot list --json=short)"
grep -qF "\"id\":\"${entry}\"" <<<"$entries"

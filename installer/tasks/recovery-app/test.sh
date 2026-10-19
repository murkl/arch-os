# The desktop reads the entry, and the script restarts into an entry the loader
# lists: systemctl refuses an unknown one only after the question was answered.
arch-chroot "$MNT" desktop-file-validate /usr/local/share/applications/arch-os-recovery.desktop
bash -n "${MNT}/usr/local/bin/arch-os-recovery"
[ -x "${MNT}/usr/local/bin/arch-os-recovery" ]

# The icon the entry names is found on every theme: hicolor is where each one
# falls back to.
icon="$(sed -n 's/^Icon=//p' "${MNT}/usr/local/share/applications/arch-os-recovery.desktop")"
[ -s "${MNT}/usr/local/share/icons/hicolor/scalable/apps/${icon}.svg" ]

entry="$(basename "$RECOVERY_EFI")"
grep -qF -- "--boot-loader-entry=\"${entry}\"" "${MNT}/usr/local/bin/arch-os-recovery"
entries="$(arch-chroot "$MNT" bootctl --esp-path=/boot list --json=short)"
grep -qF "\"id\":\"${entry}\"" <<<"$entries"

# systemctl refuses an unknown boot entry only after the dialog was confirmed.
arch-chroot "$MNT" desktop-file-validate /usr/local/share/applications/arch-os-recovery.desktop
bash -n "${MNT}/usr/local/bin/arch-os-recovery"
[ -x "${MNT}/usr/local/bin/arch-os-recovery" ]

# hicolor is the fallback of every theme.
icon="$(sed -n 's/^Icon=//p' "${MNT}/usr/local/share/applications/arch-os-recovery.desktop")"
[ -s "${MNT}/usr/local/share/icons/hicolor/scalable/apps/${icon}.svg" ]
[ -s "${MNT}/usr/local/share/icons/hicolor/symbolic/apps/${icon}-symbolic.svg" ]

entry="$(basename "$RECOVERY_EFI")"
grep -qF -- "--boot-loader-entry=\"${entry}\"" "${MNT}/usr/local/bin/arch-os-recovery"
entries="$(arch-chroot "$MNT" bootctl --esp-path=/boot list --json=short)"
grep -qF "\"id\":\"${entry}\"" <<<"$entries"

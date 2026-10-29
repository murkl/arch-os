# Besides holding Space at boot. logind lets the local session choose a boot
# entry without a password.

# zenity for the confirmation dialog.
chroot_pacman_install zenity

icons="${MNT}/usr/local/share/icons/hicolor/scalable/apps"
mkdir -p "${MNT}/usr/local/bin" "${MNT}/usr/local/share/applications" "$icons"
render "$(where)/arch-os-recovery" ENTRY="$(basename "$RECOVERY_EFI")" >"${MNT}/usr/local/bin/arch-os-recovery"
chmod 755 "${MNT}/usr/local/bin/arch-os-recovery"
render "$(where)/arch-os-recovery.desktop" >"${MNT}/usr/local/share/applications/arch-os-recovery.desktop"
render "$(where)/arch-os-recovery.svg" >"${icons}/arch-os-recovery.svg"

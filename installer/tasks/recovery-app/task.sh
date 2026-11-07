# Besides holding Space at boot. logind lets the local session choose a boot
# entry without a password.

# gjs and libadwaita for the confirmation dialog.
chroot_pacman_install gjs libadwaita

icons="${MNT}/usr/local/share/icons/hicolor"
run mkdir -p "${MNT}/usr/local/bin" "${MNT}/usr/local/share/applications" "${icons}/scalable/apps" "${icons}/symbolic/apps"
render "$(where)/arch-os-recovery" ENTRY="$(basename "$RECOVERY_EFI")" | write_file "${MNT}/usr/local/bin/arch-os-recovery"
run chmod 755 "${MNT}/usr/local/bin/arch-os-recovery"
render "$(where)/arch-os-recovery.desktop" | write_file "${MNT}/usr/local/share/applications/arch-os-recovery.desktop"
render "$(where)/arch-os-recovery.svg" | write_file "${icons}/scalable/apps/arch-os-recovery.svg"
render "$(where)/arch-os-recovery-symbolic.svg" | write_file "${icons}/symbolic/apps/arch-os-recovery-symbolic.svg"

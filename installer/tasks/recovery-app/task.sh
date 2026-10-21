# The Recovery among the applications, beside holding space at boot. logind
# lets whoever sits at the machine choose a boot entry without a password.

# zenity, for the one question the entry asks.
chroot_pacman_install zenity

icons="${MNT}/usr/local/share/icons/hicolor/scalable/apps"
mkdir -p "${MNT}/usr/local/bin" "${MNT}/usr/local/share/applications" "$icons"
render "$(where)/arch-os-recovery" ENTRY="$(basename "$RECOVERY_EFI")" >"${MNT}/usr/local/bin/arch-os-recovery"
chmod 755 "${MNT}/usr/local/bin/arch-os-recovery"
render "$(where)/arch-os-recovery.desktop" >"${MNT}/usr/local/share/applications/arch-os-recovery.desktop"
# The icon theme's own restart icon, and this one where the theme has none:
# Adwaita has it only as a symbolic icon, which an application list never draws.
render "$(where)/system-reboot.svg" >"${icons}/system-reboot.svg"

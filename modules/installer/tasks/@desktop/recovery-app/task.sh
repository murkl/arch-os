# The Recovery among the applications, beside holding space at boot. logind
# lets whoever sits at the machine choose a boot entry without a password.

# The desktop extras bring zenity, a desktop without them does not.
chroot_pacman_install zenity

icons="${MNT}/usr/local/share/icons/hicolor/scalable/apps"
mkdir -p "${MNT}/usr/local/bin" "${MNT}/usr/local/share/applications" "$icons"
render "$(where)/arch-os-recovery" ENTRY="$(basename "$RECOVERY_EFI")" >"${MNT}/usr/local/bin/arch-os-recovery"
chmod 755 "${MNT}/usr/local/bin/arch-os-recovery"
render "$(where)/arch-os-recovery.desktop" >"${MNT}/usr/local/share/applications/arch-os-recovery.desktop"
render "$(where)/arch-os-recovery.svg" >"${icons}/arch-os-recovery.svg"

# Its partition is no drive to open: the file manager would list it as one.
# Known by the partition's own UUID, which an update of the Recovery keeps.
mkdir -p "${MNT}/etc/udev/rules.d"
render "$(where)/90-arch-os-recovery.rules" PARTUUID="$(blkid -p -s PART_ENTRY_UUID -o value "$(recovery_partition "$ARCH_OS_DISK")")" \
    >"${MNT}/etc/udev/rules.d/90-arch-os-recovery.rules"

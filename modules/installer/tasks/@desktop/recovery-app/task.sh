# The Recovery among the applications, beside holding space at boot. logind
# lets whoever sits at the machine choose a boot entry without a password.

# The desktop extras bring zenity, a desktop without them does not.
chroot_pacman_install zenity

mkdir -p "${MNT}/usr/local/bin" "${MNT}/usr/local/share/applications"
render "$(where)/arch-os-recovery" ENTRY="$(basename "$RECOVERY_EFI")" >"${MNT}/usr/local/bin/arch-os-recovery"
chmod 755 "${MNT}/usr/local/bin/arch-os-recovery"
render "$(where)/arch-os-recovery.desktop" >"${MNT}/usr/local/share/applications/arch-os-recovery.desktop"

# Its partition is no drive to open: the file manager would list it as one.
mkdir -p "${MNT}/etc/udev/rules.d"
render "$(where)/90-arch-os-recovery.rules" UUID="$(blkid -p -s UUID -o value "$(recovery_partition "$ARCH_OS_DISK")")" \
    >"${MNT}/etc/udev/rules.d/90-arch-os-recovery.rules"

# The partition holds the image byte for byte, and the loader lists an entry
# that finds it by the UUID built into the image.
image="${RECOVERY_IMAGE}/recovery.img"
cmp -n "$(stat -c %s "$image")" "$image" "$RECOVERY_PART"
cmp "${RECOVERY_IMAGE}/recovery.efi" "${MNT}${RECOVERY_EFI}"

uuid="$(blkid -p -s UUID -o value "$RECOVERY_PART")"
[ -n "$uuid" ]
arch-chroot "$MNT" bootctl --esp-path=/boot list --json=short | grep -qF "archisodevice=UUID=${uuid}"

grep -qxF "ARCH_OS_RECOVERY_KEYMAP='${ARCH_OS_VCONSOLE_KEYMAP}'" "${MNT}/boot/EFI/arch-os-recovery/recovery.conf"

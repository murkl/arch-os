# The partition holds the image byte for byte, and the loader lists an entry
# that finds it by the UUID built into the image.
part="$(recovery_partition "$ARCH_OS_DISK")"
image="$(recovery_image)/recovery.img"
cmp -n "$(stat -c %s "$image")" "$image" "$part"
cmp "$(recovery_image)/recovery.efi" "${MNT}${RECOVERY_EFI}"

uuid="$(blkid -p -s UUID -o value "$part")"
[ -n "$uuid" ]
arch-chroot "$MNT" bootctl --esp-path=/boot list --json=short | grep -qF "archisodevice=UUID=${uuid}"

grep -qxF "ARCH_OS_RECOVERY_KEYMAP='$(vconsole_keymap)'" "${MNT}/boot/EFI/arch-os-recovery/recovery.conf"

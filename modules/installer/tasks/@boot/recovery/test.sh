# The partition holds the image byte for byte, and the boot loader lists an entry
# that finds it: the command line inside the image names the file system by the
# UUID it was built with, and an entry pointing anywhere else ends at a prompt.

image="${RECOVERY_IMAGE}/recovery.img"
cmp -n "$(stat -c %s "$image")" "$image" "$RECOVERY_PART"
cmp "${RECOVERY_IMAGE}/recovery.efi" "${MNT}${RECOVERY_EFI}"

uuid="$(blkid -p -s UUID -o value "$RECOVERY_PART")"
[ -n "$uuid" ]
arch-chroot "$MNT" bootctl --esp-path=/boot list --json=short | grep -qF "archisodevice=UUID=${uuid}"

# And it starts on the keyboard this installation was typed on, in the one line
# of the Recovery's answers it is handed.
grep -qxF "ARCH_OS_RECOVERY_KEYMAP='${ARCH_OS_VCONSOLE_KEYMAP}'" "${MNT}${RECOVERY_SEED}/recovery.conf"

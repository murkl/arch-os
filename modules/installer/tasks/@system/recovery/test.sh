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

# Its firmware entry starts the image on this disk's EFI partition, and is not
# in the firmware's order.
entries="$(efibootmgr)"
esp="$(blkid -p -s PART_ENTRY_UUID -o value "$(boot_partition "$ARCH_OS_DISK")")"
entry="$(awk -v esp="${esp,,}" -v efi="$(basename "$RECOVERY_EFI")" '
    !found && /^Boot[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]/ && index($0, "Arch OS Recovery") && index(tolower($0), esp) && index(tolower($0), efi) {
        print substr($1, 5, 4); found = 1
    }' <<<"$entries")"
[ -n "$entry" ]
order="$(sed -n 's/^BootOrder: //p' <<<"$entries")"
[[ ",${order}," != *",${entry},"* ]]

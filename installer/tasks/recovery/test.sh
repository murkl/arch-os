# Compared on the disk, not in the page cache, and the loader entry finds the
# partition by the image's UUID.
part="$(recovery_partition "$ARCH_OS_DISK")"
image="${RECOVERY_IMAGE}/recovery.img"
blockdev --flushbufs "$part"
cmp -n "$(stat -c %s "$image")" "$image" "$part"
cmp "${RECOVERY_IMAGE}/recovery.efi" "${MNT}${RECOVERY_EFI}"

uuid="$(blkid -p -s UUID -o value "$part")"
[ -n "$uuid" ]
arch-chroot "$MNT" bootctl --esp-path=/boot list --json=short | grep -qF "archisodevice=UUID=${uuid}"

grep -qxF "ARCH_OS_RECOVERY_KEYMAP='$ARCH_OS_VCONSOLE_KEYMAP'" "${MNT}/boot/EFI/arch-os-recovery/recovery.conf"

# The firmware entry points at this EFI partition and stays out of the boot
# order.
entries="$(efibootmgr)"
esp="$(blkid -p -s PART_ENTRY_UUID -o value "$(boot_partition "$ARCH_OS_DISK")")"
entry="$(awk -v esp="${esp,,}" -v efi="$(basename "$RECOVERY_EFI")" '
    !found && /^Boot[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]/ && index($0, "Arch OS Recovery") && index(tolower($0), esp) && index(tolower($0), efi) {
        print substr($1, 5, 4); found = 1
    }' <<<"$entries")"
[ -n "$entry" ]
order="$(sed -n 's/^BootOrder: //p' <<<"$entries")"
[[ ",${order}," != *",${entry},"* ]]

# udev skips an unreadable rule silently.
partuuid="$(blkid -p -s PART_ENTRY_UUID -o value "$(recovery_partition "$ARCH_OS_DISK")")"
[ -n "$partuuid" ]
grep -qF "\"${partuuid}\"" "${MNT}/etc/udev/rules.d/90-arch-os-recovery.rules"
udevadm verify --resolve-names=never --no-style --no-summary "${MNT}/etc/udev/rules.d/90-arch-os-recovery.rules"

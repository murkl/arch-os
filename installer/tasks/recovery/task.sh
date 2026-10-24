# systemd-boot lists EFI/Linux by itself. Boot flow:
# docs/REFERENCE.md#recovery-partition

dd if="${RECOVERY_IMAGE}/recovery.img" of="$(recovery_partition "$ARCH_OS_DISK")" bs=4M conv=fsync status=none
mkdir -p "${MNT}/boot/EFI/Linux"
cp "${RECOVERY_IMAGE}/recovery.efi" "${MNT}${RECOVERY_EFI}"

# A firmware entry for a keyboard that cannot open the loader menu. Not in the
# boot order: an Insyde firmware (Dell XPS L421X) moves it to the front.
# https://wiki.archlinux.org/title/Unified_kernel_image#Directly_from_UEFI
loader="${RECOVERY_EFI#/boot}"
efibootmgr --create-only --disk "$ARCH_OS_DISK" --part 1 --label "Arch OS Recovery" --loader "${loader//\//\\}"

# On the EFI partition, the only one readable before the passphrase. No disk:
# /dev/sda is only this boot's name.
seed="${MNT}/boot/EFI/arch-os-recovery"
mkdir -p "$seed"
render "$(where)/recovery.conf" LANGUAGE="$MODULE_LANGUAGE" KEYMAP="$(vconsole_keymap)" >"${seed}/recovery.conf"

# Hides the Recovery partition from the file manager. By PARTUUID, which a
# Recovery update keeps.
mkdir -p "${MNT}/etc/udev/rules.d"
render "$(where)/90-arch-os-recovery.rules" PARTUUID="$(blkid -p -s PART_ENTRY_UUID -o value "$(recovery_partition "$ARCH_OS_DISK")")" \
    >"${MNT}/etc/udev/rules.d/90-arch-os-recovery.rules"

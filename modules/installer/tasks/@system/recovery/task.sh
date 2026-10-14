# The Recovery on the partition left for it, and the image that starts it under
# EFI/Linux, where systemd-boot lists it by itself. Nothing is built here.
# How it boots: docs/REFERENCE.md#the-recovery-partition

image="$(recovery_image)"
dd if="${image}/recovery.img" of="$(recovery_partition "$ARCH_OS_DISK")" bs=4M conv=fsync status=none
mkdir -p "${MNT}/boot/EFI/Linux"
cp "${image}/recovery.efi" "${MNT}${RECOVERY_EFI}"

# A firmware entry for a keyboard that never brings up the loader's menu. Not in
# the boot order: an Insyde firmware (Dell XPS L421X) moves it to the front.
# https://wiki.archlinux.org/title/Unified_kernel_image#Directly_from_UEFI
loader="${RECOVERY_EFI#/boot}"
efibootmgr --create-only --disk "$ARCH_OS_DISK" --part 1 --label "Arch OS Recovery" --loader "${loader//\//\\}"

# This run's language and keyboard, on the one partition readable before the
# password. Not the disk: /dev/sda is only what this boot called it.
seed="${MNT}/boot/EFI/arch-os-recovery"
mkdir -p "$seed"
oak_conf="$(dirname "$MODULE_CONF")/oak.conf"
if [ -f "$oak_conf" ]; then
    cp "$oak_conf" "${seed}/oak.conf"
fi
render "$(where)/recovery.conf" KEYMAP="$(vconsole_keymap)" >"${seed}/recovery.conf"

# The Recovery on the partition left for it, and the image that starts it under
# EFI/Linux, where systemd-boot lists it by itself. Nothing is built here.
# How it boots: docs/REFERENCE.md#the-recovery-partition

image="$(recovery_image)"
dd if="${image}/recovery.img" of="$(recovery_partition "$ARCH_OS_DISK")" bs=4M conv=fsync status=none
mkdir -p "${MNT}/boot/EFI/Linux"
cp "${image}/recovery.efi" "${MNT}${RECOVERY_EFI}"

# An entry of its own in the firmware, outside its boot order: the firmware's
# boot menu starts it on a machine whose keyboard never brings up the loader's.
# Not in the order, since an Insyde firmware (Dell XPS L421X) moves an entry it
# finds there to the front of its own list and starts it every time. Written
# from out here, like the loader's entry.
# https://wiki.archlinux.org/title/Unified_kernel_image#Directly_from_UEFI
loader="${RECOVERY_EFI#/boot}"
efibootmgr --create-only --disk "$ARCH_OS_DISK" --part 1 --label "Arch OS Recovery" --loader "${loader//\//\\}"

# It starts in this run's language and on this run's keyboard instead of asking.
# On the EFI partition, the one part of an encrypted disk readable before the
# password; iso/recovery/ copies them out of the same path. The disk is not
# among them: /dev/sda is only what this boot called it.
seed="${MNT}/boot/EFI/arch-os-recovery"
mkdir -p "$seed"
oak_conf="$(dirname "$MODULE_CONF")/oak.conf"
if [ -f "$oak_conf" ]; then
    cp "$oak_conf" "${seed}/oak.conf"
fi
render "$(where)/recovery.conf" KEYMAP="$(vconsole_keymap)" >"${seed}/recovery.conf"

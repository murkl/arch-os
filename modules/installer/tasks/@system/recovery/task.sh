# The Recovery on the partition left for it, and the image that starts it under
# EFI/Linux, where systemd-boot lists it by itself. Nothing is built here.
# How it boots: docs/REFERENCE.md#the-recovery-partition

dd if="${RECOVERY_IMAGE}/recovery.img" of="$RECOVERY_PART" bs=4M conv=fsync status=none
mkdir -p "${MNT}/boot/EFI/Linux"
cp "${RECOVERY_IMAGE}/recovery.efi" "${MNT}${RECOVERY_EFI}"

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
render "$(where)/recovery.conf" KEYMAP="$ARCH_OS_VCONSOLE_KEYMAP" >"${seed}/recovery.conf"

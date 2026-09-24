# The Recovery on the partition the disk stage left for it, and the image that
# starts it beside the system's own. Both come ready-made with the live image:
# nothing is built here, the partition is written as it is. How it boots:
# docs/REFERENCE.md

dd if="${RECOVERY_IMAGE}/recovery.img" of="$RECOVERY_PART" bs=4M conv=fsync status=none

mkdir -p "${MNT}/boot/EFI/Linux"
cp "${RECOVERY_IMAGE}/recovery.efi" "${MNT}${RECOVERY_EFI}"

# It starts in the language this installation was read in and on the keyboard
# it was typed on, rather than asking for either: Oak's own answers as they
# stand beside this run's, and the one answer of the Recovery's that is known
# here. The disk is not among them - a name like /dev/sda is only what this
# boot called it, so the Recovery works it out from where it was started.
mkdir -p "${MNT}${RECOVERY_SEED}"
oak_conf="$(dirname "$MODULE_CONF")/oak.conf"
if [ -f "$oak_conf" ]; then
    cp "$oak_conf" "${MNT}${RECOVERY_SEED}/oak.conf"
fi
render "$(where)/recovery.conf" KEYMAP="$ARCH_OS_VCONSOLE_KEYMAP" >"${MNT}${RECOVERY_SEED}/recovery.conf"

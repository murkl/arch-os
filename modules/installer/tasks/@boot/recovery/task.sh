# The Recovery on the partition the disk stage left for it, and the image that
# starts it beside the system's own. Both come ready-made with the live image:
# nothing is built here, the partition is written as it is. How it boots:
# docs/REFERENCE.md

dd if="${RECOVERY_IMAGE}/recovery.img" of="$RECOVERY_PART" bs=4M conv=fsync status=none

mkdir -p "${MNT}/boot/EFI/Linux"
cp "${RECOVERY_IMAGE}/recovery.efi" "${MNT}${RECOVERY_EFI}"

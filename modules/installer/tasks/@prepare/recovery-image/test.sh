# Both halves of the Recovery are where the disk stage and the Recovery task
# read them, and neither is empty.

[ -s "${RECOVERY_IMAGE}/recovery.img" ]
[ -s "${RECOVERY_IMAGE}/recovery.efi" ]

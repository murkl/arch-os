# Every subvolume mounted where it belongs. An unmounted one would leave the
# repair working on the empty directory inside @.
mountpoint -q "$MNT"
[ -f "${MNT}/etc/os-release" ]
[ "$(findmnt -no SOURCE "${MNT}/boot")" = "$(boot_partition "$ARCH_OS_RECOVERY_DISK")" ]
while IFS=$'\t' read -r subvolume path; do
    findmnt -no OPTIONS "${MNT}${path%/}" | grep -qE "(^|,)subvol=/${subvolume}(,|$)"
done < <(btrfs_subvolumes)

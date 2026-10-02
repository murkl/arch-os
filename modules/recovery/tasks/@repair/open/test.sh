# Every subvolume mounted where it belongs: one left unmounted would have the
# repair work on the empty directory inside @ instead.
mountpoint -q "$MNT"
[ -f "${MNT}/etc/os-release" ]
[ "$(findmnt -no SOURCE "${MNT}/boot")" = "$(boot_partition "$ARCH_OS_RECOVERY_DISK")" ]
while IFS=$'\t' read -r subvolume path; do
    findmnt -no OPTIONS "${MNT}${path%/}" | grep -qE "(^|,)subvol=/${subvolume}(,|$)"
done < <(btrfs_subvolumes)

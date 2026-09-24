# The system is reachable at the mount point everything after this writes
# through, and every subvolume is mounted where it belongs. A subvolume that is
# there and was not mounted would go unnoticed otherwise: the repair would work
# on the empty directory inside @ instead of on the logs or the cache in use.

mountpoint -q "$MNT"
[ -f "${MNT}/etc/os-release" ]

while IFS=$'\t' read -r subvolume path; do
    findmnt -no OPTIONS "${MNT}${path%/}" | grep -qE "(^|,)subvol=/${subvolume}(,|$)"
done < <(btrfs_subvolumes)

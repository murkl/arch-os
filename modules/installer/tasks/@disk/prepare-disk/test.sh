# The two mount points every later task writes through, and on btrfs that each
# subvolume is mounted where the layout says rather than only created.
#
# A subvolume made and not mounted leaves an ordinary directory inside @ at that
# path, which fills up, rides along in every snapshot and comes back with every
# rollback - and nothing after this would notice, because a directory answers
# every question a mount point does.

mountpoint -q "$MNT"
mountpoint -q "${MNT}/boot"

# Encrypted, the system goes onto the opened volume on the root partition - not
# onto the partition underneath, which would install it in the clear.
if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
    root_source="$(findmnt -no SOURCE "$MNT")"
    [[ $root_source == /dev/mapper/cryptroot* ]]
    [ "$(cryptsetup status cryptroot | awk '$1 == "device:" { print $2 }')" = "$ROOT_PART" ]
fi

[ "$ARCH_OS_FILESYSTEM" = "btrfs" ] || return 0

# Asked of the kernel's own mount table rather than of the file system: what
# matters is which subvolume is reachable at that path now.
while IFS=$'\t' read -r subvolume path; do
    findmnt -no OPTIONS "${MNT}${path%/}" | grep -qE "(^|,)subvol=/${subvolume}(,|$)"
done < <(btrfs_subvolumes)

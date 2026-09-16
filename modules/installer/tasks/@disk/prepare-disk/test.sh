# The two mount points every later task writes through. Checking them here is
# what turns "the disk was set up" into something read off the machine.
#
# And on btrfs, that each subvolume is mounted where the layout says rather than
# only created: one that was made and not mounted leaves an ordinary directory
# inside @ at that path, which fills up, rides along in every snapshot and comes
# back with every rollback. Nothing after this step would notice, because a
# directory answers every question a mount point does.
debugging && return 0

mountpoint -q "$MNT"
mountpoint -q "${MNT}/boot"

[ "$ARCH_OS_FILESYSTEM" = "btrfs" ] || return 0

# Asked of the kernel's own mount table rather than of the file system: what
# matters is which subvolume is reachable at that path now.
while IFS=$'\t' read -r subvolume path; do
    findmnt -no OPTIONS "${MNT}${path%/}" | grep -qE "(^|,)subvol=/${subvolume}(,|$)"
done < <(btrfs_subvolumes)

# The system is reachable at the mount point everything after this writes
# through, and on btrfs every subvolume this particular disk has is mounted
# where it belongs.
#
# The list is read off the disk rather than demanded: an installation from an
# earlier version has three subvolumes and a newer one six, and both are systems
# this has to open. What would go unnoticed is the other case - a subvolume that
# is there and was not mounted, where the repair then works on the empty
# directory inside @ instead of on the logs or the cache actually in use.
debugging && return 0

mountpoint -q "$MNT"
[ -f "${MNT}/etc/os-release" ]

on_btrfs || return 0

present="$(btrfs subvolume list "$MNT" | awk '{ print $NF }')"

while IFS=$'\t' read -r subvolume path; do
    [ "$subvolume" = "@" ] && continue
    printf '%s\n' "$present" | grep -qxF "$subvolume" || continue
    findmnt -no OPTIONS "${MNT}${path}" | grep -qE "(^|,)subvol=/${subvolume}(,|$)"
done < <(btrfs_subvolumes)

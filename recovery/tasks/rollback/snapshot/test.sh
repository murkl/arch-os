# Read off btrfs: a run that gave up and left the old @ looks the same from out
# here. A snapshot carries its origin's UUID as the parent of @.

# One field of `btrfs subvolume show`, anchored so UUID does not answer for the
# parent; sed ends at the first match and still reads to the end.
subvolume_field() {
    btrfs subvolume show "$1" | sed -n "0,/^[[:space:]]*${2}:/s/^[[:space:]]*${2}:[[:space:]]*//p"
}

mountpoint -q "$MNT"
[ ! -e "${BTRFS_TOP}/@.new" ]

parent="$(subvolume_field "${BTRFS_TOP}/@" "Parent UUID")"
chosen="$(subvolume_field "${BTRFS_TOP}/${ARCH_OS_RECOVERY_SNAPSHOT}" "UUID")"
[ -n "$chosen" ] && [ "$parent" = "$chosen" ]

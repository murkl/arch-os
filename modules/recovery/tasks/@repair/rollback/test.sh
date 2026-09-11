# Read off btrfs rather than off the fact that nothing failed: a run that gave
# up halfway and left the old @ standing looks exactly the same from out here.
#
# A snapshot carries the identity of what it was taken from, so the parent of @
# is the one thing that says which snapshot it now holds.
debugging && return 0

# One field of `btrfs subvolume show`, which prints them one per line as
# "<name>:<tab><value>". Anchored on the name, so UUID does not also answer for
# the parent.
subvolume_field() {
    btrfs subvolume show "$1" | sed -n "s/^[[:space:]]*${2}:[[:space:]]*//p" | head -n1
}

mountpoint -q "$MNT"

# The half-built subvolume is gone, so a second rollback starts from a clean top
# level rather than from what this one left lying there.
[ ! -e "${BTRFS_TOP}/@.new" ]

parent="$(subvolume_field "${BTRFS_TOP}/@" "Parent UUID")"
chosen="$(subvolume_field "${BTRFS_TOP}/${ARCH_OS_RECOVERY_SNAPSHOT}" "UUID")"
[ -n "$chosen" ] && [ "$parent" = "$chosen" ]

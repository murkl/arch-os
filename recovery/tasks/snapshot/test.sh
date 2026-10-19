# Read off btrfs: a run that gave up and left the old @ looks the same from out
# here. A snapshot carries its origin's UUID as the parent of @.

# One field of `btrfs subvolume show`, anchored so UUID does not answer for the
# parent. sed ends at the first match and still reads to the end.
subvolume_field() {
    btrfs subvolume show "$1" | sed -n "0,/^[[:space:]]*${2}:/s/^[[:space:]]*${2}:[[:space:]]*//p"
}

mountpoint -q "$MNT"
[ ! -e "${BTRFS_TOP}/@.new" ]

parent="$(subvolume_field "${BTRFS_TOP}/@" "Parent UUID")"
chosen="$(subvolume_field "${BTRFS_TOP}/${ARCH_OS_RECOVERY_SNAPSHOT}" "UUID")"
[ -n "$chosen" ] && [ "$parent" = "$chosen" ]

# The system it replaced, read-only under the newest number.
newest="$(find "${BTRFS_TOP}/@snapshots" -mindepth 1 -maxdepth 1 -regex '.*/[0-9]+' -printf '%f\n' | sort -n | tail -n1)"
grep -qF '<description>rollback backup</description>' "${BTRFS_TOP}/@snapshots/${newest}/info.xml"
[ "$(btrfs property get -ts "${BTRFS_TOP}/@snapshots/${newest}/snapshot" ro)" = "ro=true" ]

# Read from btrfs, since a run that left the old @ looks the same from outside.
# @ carries the chosen snapshot's UUID as its parent UUID.

# Anchored, so UUID does not match Parent UUID. sed stops printing after the
# first match and still reads to the end.
subvolume_field() {
    btrfs subvolume show "$1" | sed -n "0,/^[[:space:]]*${2}:/s/^[[:space:]]*${2}:[[:space:]]*//p"
}

mountpoint -q "$MNT"
[ ! -e "${BTRFS_TOP}/@.new" ]

parent="$(subvolume_field "${BTRFS_TOP}/@" "Parent UUID")"
chosen="$(subvolume_field "${BTRFS_TOP}/${ARCH_OS_RECOVERY_SNAPSHOT}" "UUID")"
[ -n "$chosen" ] && [ "$parent" = "$chosen" ]

# The replaced system, read-only under the newest number.
newest="$(find "${BTRFS_TOP}/@snapshots" -mindepth 1 -maxdepth 1 -regex '.*/[0-9]+' -printf '%f\n' | sort -n | tail -n1)"
grep -qF '<description>rollback backup</description>' "${BTRFS_TOP}/@snapshots/${newest}/info.xml"
[ "$(btrfs property get -ts "${BTRFS_TOP}/@snapshots/${newest}/snapshot" ro)" = "ro=true" ]

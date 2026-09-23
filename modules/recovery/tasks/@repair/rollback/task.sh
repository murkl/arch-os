# The chosen snapshot put in place of the root subvolume, and what came out of
# it mounted in place of what was there.
#
# The new @ is built before the old one is touched, so a rollback that dies
# halfway leaves the system as it found it rather than with no root at all.
# https://wiki.archlinux.org/title/Btrfs#Restoring_a_snapshot

snapshot="$ARCH_OS_RECOVERY_SNAPSHOT"

if [ ! -d "${BTRFS_TOP}/${snapshot}" ]; then
    echo "There is no snapshot at ${snapshot}." >&2
    return 1
fi

# @ cannot be replaced while it is the root that is mounted. Anything still
# holding it open is named in the log and killed first.
unmount_target

btrfs subvolume delete --recursive "${BTRFS_TOP}/@.new" 2>/dev/null || true
btrfs subvolume snapshot "${BTRFS_TOP}/${snapshot}" "${BTRFS_TOP}/@.new"
btrfs subvolume delete --recursive "${BTRFS_TOP}/@"
mv "${BTRFS_TOP}/@.new" "${BTRFS_TOP}/@"

mount_target

# A lock left behind by the transaction that broke this system would stop the
# recovered one from being repaired further.
rm -f "${MNT}/var/lib/pacman/db.lck"

echo "@ is now ${snapshot}"

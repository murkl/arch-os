# Put the chosen snapshot in place of the root subvolume, and mount what came out
# of it in place of what was there.
#
# The new @ is built before the old one is touched, so a rollback that dies
# halfway leaves the system as it found it rather than with no root at all.

simulating && return 0

snapshot="$ARCH_OS_RECOVERY_SNAPSHOT"

if [ ! -d "${BTRFS_TOP}/${snapshot}" ]; then
    echo "There is no snapshot at ${snapshot}." >&2
    return 1
fi

# @ cannot be replaced while it is the root that is mounted. Anything still
# holding it open is named in the log and killed first, the same way closing the
# system does it - a rollback that stops here leaves the machine exactly as it
# found it, but it should not stop for a process nobody is using.
if ! umount -A -R "$MNT"; then
    free_target
    umount -A -R "$MNT"
fi

btrfs subvolume delete --recursive "${BTRFS_TOP}/@.new" 2>/dev/null || true
btrfs subvolume snapshot "${BTRFS_TOP}/${snapshot}" "${BTRFS_TOP}/@.new"
btrfs subvolume delete --recursive "${BTRFS_TOP}/@"
mv "${BTRFS_TOP}/@.new" "${BTRFS_TOP}/@"

mount_system

# A lock left behind by the transaction that broke this system would stop the
# recovered one from being repaired further.
rm -f "${MNT}/var/lib/pacman/db.lck"

echo "@ is now ${snapshot}"

# The snapshot in place of @. The new @ is built before the old one is touched,
# so a rollback that dies halfway leaves the system as it was.
# https://wiki.archlinux.org/title/Btrfs#Restoring_a_snapshot

snapshot="$ARCH_OS_RECOVERY_SNAPSHOT"
if [ ! -d "${BTRFS_TOP}/${snapshot}" ]; then
    echo "There is no snapshot at ${snapshot}." >&2
    return 1
fi

# @ cannot be replaced while it is the mounted root.
unmount_target

btrfs subvolume delete --recursive "${BTRFS_TOP}/@.new" 2>/dev/null || true
btrfs subvolume snapshot "${BTRFS_TOP}/${snapshot}" "${BTRFS_TOP}/@.new"

# The Secure Boot keys belong to the firmware, not to a point in time: a
# snapshot from before them could sign nothing it rebuilds.
if [ -d "${BTRFS_TOP}/@/var/lib/sbctl" ]; then
    rm -rf "${BTRFS_TOP}/@.new/var/lib/sbctl"
    cp -a "${BTRFS_TOP}/@/var/lib/sbctl" "${BTRFS_TOP}/@.new/var/lib/sbctl"
fi

btrfs subvolume delete --recursive "${BTRFS_TOP}/@"
mv "${BTRFS_TOP}/@.new" "${BTRFS_TOP}/@"
mount_target

# The lock of the transaction that broke it would stop further repairs.
rm -f "${MNT}/var/lib/pacman/db.lck"

echo "@ is now ${snapshot}"

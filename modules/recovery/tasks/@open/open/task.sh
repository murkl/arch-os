# The installation being repaired: unlocked where the disk is encrypted, and
# mounted at /mnt the way that system mounts itself.

# A second attempt starts from whatever the first one left behind.
close_target

if [ ! -b "$ROOT_PART" ]; then
    echo "There is no partition at ${ROOT_PART}. That disk does not hold an Arch OS installation." >&2
    exit 1
fi

# The password goes in on stdin and never reaches a command line, which /proc
# would show.
if [ "$ARCH_OS_RECOVERY_ENCRYPTED" = "true" ]; then
    if ! printf '%s' "$ARCH_OS_RECOVERY_PASSWORD" | cryptsetup open "$ROOT_PART" "$CRYPT"; then
        echo "The password did not unlock ${ROOT_PART}." >&2
        return 1
    fi
fi

# What is on it, now that it can be seen. Nothing readable here is a disk this
# recovery has no business mounting.
found="$(fstype "$(root_device)")"
if [ -z "$found" ]; then
    echo "There is no file system on $(root_device) that this machine recognises." >&2
    return 1
fi

# The top level first, where a rollback does its work, and only then the system
# as it runs.
if on_btrfs; then
    mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvolid=5" "$(root_device)" "$BTRFS_TOP"
fi
mount_target

echo "opened ${ARCH_OS_RECOVERY_DISK} at ${MNT} (${found})"

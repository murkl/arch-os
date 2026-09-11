# Open the installation being repaired: the disk unlocked where it is encrypted,
# checked to be the system it was answered to be, and mounted at /mnt the way
# that system mounts itself.

simulating && return 0

# A second attempt starts from whatever the first one left behind.
close_target

root="$(root_part)"
if [ ! -b "$root" ]; then
    echo "There is no partition at ${root}. That disk does not hold an Arch OS installation." >&2
    exit 1
fi

# The password goes in on stdin and never reaches a command line, which /proc
# would show.
if [ "$ARCH_OS_RECOVERY_ENCRYPTION_ENABLED" = "true" ]; then
    if ! printf '%s' "$ARCH_OS_RECOVERY_PASSWORD" | cryptsetup open "$root" "$CRYPT"; then
        echo "The password did not unlock ${root}." >&2
        return 1
    fi
fi

# What is actually on it, now that it can be seen - so a wrong answer is caught
# here rather than by a mount command that names no question.
found="$(fstype "$(root_device)")"
if [ "$found" != "$ARCH_OS_RECOVERY_FILESYSTEM" ]; then
    echo "That disk holds ${found:-nothing recognisable}, not ${ARCH_OS_RECOVERY_FILESYSTEM}." >&2
    return 1
fi

# The top level first, where a rollback does its work, and only then the system
# as it runs.
if [ "$ARCH_OS_RECOVERY_FILESYSTEM" = "btrfs" ]; then
    mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvolid=5" "$(root_device)" "$BTRFS_TOP"
fi
mount_target

echo "opened ${ARCH_OS_RECOVERY_DISK} at ${MNT}"

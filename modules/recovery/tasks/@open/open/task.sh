# The installation being repaired: unlocked where the disk is encrypted, and
# mounted at /mnt the way that system mounts itself.

# A second attempt starts from whatever the first one left behind.
close_target

if [ -z "$ROOT_PART" ]; then
    echo "${ARCH_OS_RECOVERY_DISK} holds no Arch OS installation: its second partition is neither a LUKS container nor a btrfs labelled BTRFS." >&2
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

# What is on it, now that it can be seen. Anything but btrfs is a disk this
# recovery has no business mounting.
if [ "$(fstype "$(root_device)")" != "btrfs" ]; then
    echo "There is no btrfs on $(root_device), so it holds no Arch OS installation." >&2
    return 1
fi

# The top level first, where a rollback does its work and where the layout can
# be read, and only then the system as it runs. Every subvolume the Installer
# lays down has to be there: a disk short of one was installed by an earlier
# release, and is opened by that release's Recovery.
mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvolid=5" "$(root_device)" "$BTRFS_TOP"
missing="$(missing_subvolumes)"
if [ -n "$missing" ]; then
    echo "${ARCH_OS_RECOVERY_DISK} was installed by an earlier release of Arch OS and has no $(paste -sd ' ' <<<"$missing"). Open it with the Recovery of the release it was installed with." >&2
    return 1
fi
mount_target

echo "opened ${ARCH_OS_RECOVERY_DISK} at ${MNT}"

# Unlocks the installation and mounts it at /mnt as it mounts itself.

# A second attempt starts from what the first left half open.
close_target
echo "closed ${MNT}"

part="$(target_partition)"
if [ -z "$part" ]; then
    echo "${ARCH_OS_RECOVERY_DISK} holds no Arch OS installation: partition 2 is neither LUKS nor btrfs labeled BTRFS." >&2
    exit 10
fi

# On stdin, never on a command line visible in /proc.
if [ "$ARCH_OS_RECOVERY_ENCRYPTED" = "true" ]; then
    if ! printf '%s' "$ARCH_OS_RECOVERY_PASSWORD" | cryptsetup open "$part" "$CRYPT"; then
        echo "The password did not unlock ${part}." >&2
        return 1
    fi
fi

device="$(target_device)"
if [ "$(fstype "$device")" != "btrfs" ]; then
    echo "No btrfs on ${device}, so no Arch OS installation." >&2
    exit 10
fi

# The top level first, where a rollback works and the layout shows.
mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvolid=5" "$device" "$BTRFS_TOP"

# A rollback interrupted between removing the old @ and moving in the new one.
if [ ! -e "${BTRFS_TOP}/@" ] && [ -d "${BTRFS_TOP}/@.new" ]; then
    mv "${BTRFS_TOP}/@.new" "${BTRFS_TOP}/@"
    echo "finished an interrupted rollback"
fi

present="$(btrfs subvolume list "$BTRFS_TOP" | awk '{ print $NF }')"
missing=()
while read -r subvolume _; do
    grep -qxF "$subvolume" <<<"$present" || missing+=("$subvolume")
done < <(btrfs_subvolumes)
if [ "${#missing[@]}" -gt 0 ]; then
    echo "${ARCH_OS_RECOVERY_DISK} lacks ${missing[*]}, which the Installer of this release creates." >&2
    exit 11
fi
mount_target

echo "opened ${ARCH_OS_RECOVERY_DISK} at ${MNT}"

# The installation unlocked and mounted at /mnt the way it mounts itself.

# A second attempt starts from whatever the first left half open: the system
# closed for good, before opening as after. A system still standing cannot be
# locked either.
swapoff -a || true
sync
unmount_target
if mountpoint -q "$BTRFS_TOP"; then
    umount -R "$BTRFS_TOP"
fi
if [ -e "/dev/mapper/${CRYPT}" ]; then
    cryptsetup close "$CRYPT"
fi
echo "closed ${MNT}"

part="$(target_partition)"
if [ -z "$part" ]; then
    echo "${ARCH_OS_RECOVERY_DISK} holds no Arch OS installation: its second partition is neither a LUKS container nor a btrfs labelled BTRFS." >&2
    exit 1
fi

# On stdin, never on a command line /proc shows.
if [ "$ARCH_OS_RECOVERY_ENCRYPTED" = "true" ]; then
    if ! printf '%s' "$ARCH_OS_RECOVERY_PASSWORD" | cryptsetup open "$part" "$CRYPT"; then
        echo "The password did not unlock ${part}." >&2
        return 1
    fi
fi

device="$(target_device)"
if [ "$(fstype "$device")" != "btrfs" ]; then
    echo "There is no btrfs on ${device}, so it holds no Arch OS installation." >&2
    return 1
fi

# The top level first, where a rollback works and the layout can be read. A disk
# short of a subvolume was installed by an earlier release, and is opened by
# that release's Recovery.
mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvolid=5" "$device" "$BTRFS_TOP"

# A rollback stopped between taking the old @ away and moving the new one in.
if [ ! -e "${BTRFS_TOP}/@" ] && [ -d "${BTRFS_TOP}/@.new" ]; then
    mv "${BTRFS_TOP}/@.new" "${BTRFS_TOP}/@"
    echo "finished the rollback an earlier run left halfway"
fi

present="$(btrfs subvolume list "$BTRFS_TOP" | awk '{ print $NF }')"
missing=()
while read -r subvolume _; do
    grep -qxF "$subvolume" <<<"$present" || missing+=("$subvolume")
done < <(btrfs_subvolumes)
if [ "${#missing[@]}" -gt 0 ]; then
    echo "${ARCH_OS_RECOVERY_DISK} was installed by an earlier release of Arch OS and has no ${missing[*]}. Open it with the Recovery of the release it was installed with." >&2
    return 1
fi
mount_target

echo "opened ${ARCH_OS_RECOVERY_DISK} at ${MNT}"

# Partition, encrypt, format and mount the target. The only stage that destroys
# data: everything before it is reversible by walking away.

simulating && return 0

# How this project mounts btrfs. The recovery mounts what this lays down and has
# the same line in its own lib.sh — the two must not drift apart.
BTRFS_OPTS="defaults,noatime,compress=zstd"

# Dual boot keeps the disk as it is — the other system's partitions, its EFI
# partition and its boot entries all stay.
if [ "$ARCH_OS_DUAL_BOOT_ENABLED" != "true" ]; then
    wipefs -af "$ARCH_OS_DISK"
    sgdisk --zap-all "$ARCH_OS_DISK"
    sgdisk -o "$ARCH_OS_DISK"
    sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot --align-end "$ARCH_OS_DISK"
    sgdisk -n 2:0:0 -t 2:8300 -c 2:root --align-end "$ARCH_OS_DISK"
    partprobe "$ARCH_OS_DISK"
fi

# On stdin, so the passphrase never reaches an argument list that /proc shows.
root_device="$ARCH_OS_ROOT_PARTITION"
if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
    echo "encrypting ${ARCH_OS_ROOT_PARTITION}"
    printf '%s' "$ARCH_OS_PASSWORD" | cryptsetup luksFormat "$ARCH_OS_ROOT_PARTITION"
    printf '%s' "$ARCH_OS_PASSWORD" | cryptsetup open "$ARCH_OS_ROOT_PARTITION" cryptroot
    root_device=/dev/mapper/cryptroot
fi

# Only formatted when this installer created it: formatting one that was already
# there would take the other system's boot loader with it.
[ "$ARCH_OS_DUAL_BOOT_ENABLED" != "true" ] && mkfs.fat -F 32 -n BOOT "$ARCH_OS_BOOT_PARTITION"

if [ "$ARCH_OS_FILESYSTEM" = "ext4" ]; then
    mkfs.ext4 -F -L ROOT "$root_device"
    mount -v "$root_device" "$MNT"
fi

if [ "$ARCH_OS_FILESYSTEM" = "btrfs" ]; then
    mkfs.btrfs -f -L BTRFS "$root_device"
    mount -v "$root_device" "$MNT"

    # The system, the home directories and the snapshots are separate things to
    # roll back or keep.
    btrfs subvolume create "${MNT}/@"
    btrfs subvolume create "${MNT}/@home"
    btrfs subvolume create "${MNT}/@snapshots"
    umount -R "$MNT"

    mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=@" "$root_device" "$MNT"
    mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=@home" "$root_device" "${MNT}/home"
    mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=@snapshots" "$root_device" "${MNT}/.snapshots"

    # systemd would otherwise make subvolumes of these on first boot, which show
    # up in every snapshot listing as noise.
    mkdir -p "${MNT}/var/lib/portables" "${MNT}/var/lib/machines"
fi

mount -v --mkdir "$ARCH_OS_BOOT_PARTITION" "${MNT}/boot"

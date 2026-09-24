# Partition, encrypt, format and mount the target. The only stage that destroys
# data: everything before it is reversible by walking away.
# https://wiki.archlinux.org/title/Installation_guide#Partition_the_disks
#
# The layout and the subvolumes: docs/REFERENCE.md

# /dev/sda is a path, not a disk: an answer file carried over from another
# machine names whatever sat there, and here that can be another disk or the
# medium this live image runs from. So the answer is checked against the list
# it is chosen from, immediately before anything is written.
disks="$(list_disks | cut -f1)"
if ! grep -qxF "$ARCH_OS_DISK" <<<"$disks"; then
    echo "${ARCH_OS_DISK} is not one of the disks this machine can be installed on. Choose the disk again in the settings." >&2
    exit 1
fi

# What still holds a partition of it - a file system or a LUKS volume opened by
# hand, swap on it - keeps the kernel from reading the new table, and partprobe
# would say so only after the old one is gone. The init task has already closed
# everything this Installer opens itself.
#
# Raw output, where a partition mounted twice - btrfs subvolumes - has its
# mount points joined by an escaped newline.
held="$(lsblk -nrpo NAME,TYPE,MOUNTPOINTS "$ARCH_OS_DISK" | awk -F'[ ]' '
    ($2 != "disk" && $2 != "part") || $3 != "" {
        gsub(/\\x0a/, ", ", $3)
        printf "%s %s%s", sep, $1, ($3 == "" ? "" : " at " $3); sep = ";"
    }')"
if [ -n "$held" ]; then
    echo "${ARCH_OS_DISK} is still in use:${held}. Close or unmount that, then start again." >&2
    exit 1
fi

# Which partitions the disk holds now, asked before the table is wiped: once it
# is gone, nothing says any more which of the firmware's boot entries were
# pointing at this disk.
old_parts="$(lsblk -nro PARTUUID "$ARCH_OS_DISK" | awk 'NF { printf "%s ", tolower($1) }')"

wipefs -af "$ARCH_OS_DISK"
sgdisk --zap-all "$ARCH_OS_DISK"
sgdisk -o "$ARCH_OS_DISK"
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot --align-end "$ARCH_OS_DISK"
sgdisk -n 2:0:0 -t 2:8300 -c 2:root --align-end "$ARCH_OS_DISK"
partprobe "$ARCH_OS_DISK"

# partprobe tells the kernel to re-read the table; the device nodes under it are
# udev's, and it makes them a moment later. Without the wait the format below
# runs against a path that is not there yet.
udevadm settle

# The firmware's entries for what was on the disk - a Windows Boot Manager, an
# earlier installation - now point at partitions that are gone, and its boot
# menu would go on offering them. An entry naming another disk is left alone.
# Not fatal: one left behind costs a line in a menu, not the installation.
# https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface#efibootmgr
if [ -n "$old_parts" ]; then
    if entries="$(efibootmgr)"; then
        while read -r entry; do
            echo "removing boot entry ${entry}, which pointed at a partition that is gone"
            efibootmgr -q -b "$entry" -B || echo "boot entry ${entry} could not be removed" >&2
        done < <(awk -v parts="$old_parts" '
            BEGIN { n = split(parts, part, " ") }
            /^Boot[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][* ]/ {
                line = tolower($0)
                for (i = 1; i <= n; i++) if (index(line, part[i])) { print substr($1, 5, 4); break }
            }' <<<"$entries")
    else
        echo "the firmware's boot entries could not be read, so the old ones are still listed" >&2
    fi
fi

# On stdin, so the passphrase never reaches an argument list that /proc shows.
root_device="$ROOT_PART"
if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
    echo "encrypting ${ROOT_PART}"
    printf '%s' "$ARCH_OS_PASSWORD" | cryptsetup luksFormat "$ROOT_PART"
    printf '%s' "$ARCH_OS_PASSWORD" | cryptsetup open "$ROOT_PART" cryptroot
    root_device=/dev/mapper/cryptroot
fi

mkfs.fat -F 32 -n BOOT "$BOOT_PART"

if [ "$ARCH_OS_FILESYSTEM" = "ext4" ]; then
    mkfs.ext4 -F -L ROOT "$root_device"
    mount -v "$root_device" "$MNT"
fi

if [ "$ARCH_OS_FILESYSTEM" = "btrfs" ]; then
    mkfs.btrfs -f -L BTRFS "$root_device"
    mount -v "$root_device" "$MNT"

    # One per thing that is rolled back, kept or thrown away on its own.
    while read -r subvolume _; do
        btrfs subvolume create "${MNT}/${subvolume}"
    done < <(btrfs_subvolumes)
    umount -R "$MNT"

    # @ first, since every other mount point is a directory inside it.
    while IFS=$'\t' read -r subvolume path; do
        mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=${subvolume}" \
            "$root_device" "${MNT}${path%/}"
    done < <(btrfs_subvolumes)

    # A fresh subvolume is root's alone, and /var/tmp is where anything on the
    # machine may write. systemd-tmpfiles would set this at the first boot; the
    # installation writes there before there is one.
    chmod 1777 "${MNT}/var/tmp"

    # systemd would otherwise make subvolumes of these on first boot, which show
    # up in every snapshot listing as noise.
    mkdir -p "${MNT}/var/lib/portables" "${MNT}/var/lib/machines"
fi

mount -v --mkdir "$BOOT_PART" "${MNT}/boot"

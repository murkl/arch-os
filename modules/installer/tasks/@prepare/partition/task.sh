# Partition, encrypt, format and mount the target. The layout and the
# subvolumes: docs/REFERENCE.md
# https://wiki.archlinux.org/title/Installation_guide#Partition_the_disks

# An answer file from another machine names whatever sat at that path there, so
# the disk is held to the list it is chosen from right before it is written.
disks="$(list_disks | cut -f1)"
if ! grep -qxF "$ARCH_OS_DISK" <<<"$disks"; then
    echo "${ARCH_OS_DISK} is not one of the disks this machine can be installed on. Choose the disk again in the settings." >&2
    exit 1
fi
boot_part="$(boot_partition "$ARCH_OS_DISK")"
system_part="$(system_partition "$ARCH_OS_DISK")"

# What an earlier attempt left mounted, closed for good. -M keeps fuser on the
# target: without it, a target that is no mount point resolves to the live
# image. See docs/REFERENCE.md#closing-the-target
swapoff -a || true
sync
if mountpoint -q "$MNT" && ! umount -R "$MNT"; then
    echo "the target did not unmount, what is holding it:"
    fuser -Mvm "$MNT" || true
    fuser -Mkm "$MNT" || true
    sleep 2 # the kernel needs a moment to let go of the files
    umount -R "$MNT"
fi
if [ -e /dev/mapper/cryptroot ]; then
    cryptsetup close cryptroot
fi

# An LVM group or a software RAID the live image assembled on its own off the
# old contents holds the partitions open. lvm warns about every descriptor it
# inherits, Oak's error channel among them.
LVM_SUPPRESS_FD_WARNINGS=1 vgchange -an || true
if command -v mdadm >/dev/null; then
    mdadm --stop --scan || true
fi

# Anything else still holding a partition - opened by hand, swap on it - keeps
# the kernel from reading the new table. Raw output joins two mount points of
# one partition with an escaped newline.
held="$(lsblk -nrpo NAME,TYPE,MOUNTPOINTS "$ARCH_OS_DISK" | awk -F'[ ]' '
    ($2 != "disk" && $2 != "part") || $3 != "" {
        gsub(/\\x0a/, ", ", $3)
        printf "%s %s%s", sep, $1, ($3 == "" ? "" : " at " $3); sep = ";"
    }')"
if [ -n "$held" ]; then
    echo "${ARCH_OS_DISK} is still in use:${held}. Close or unmount that, then start again." >&2
    exit 1
fi

# Asked before the table is wiped: afterwards nothing says which firmware
# entries pointed at this disk.
old_parts="$(lsblk -nro PARTUUID "$ARCH_OS_DISK" | awk 'NF { printf "%s ", tolower($1) }')"

wipefs -af "$ARCH_OS_DISK"
sgdisk --zap-all "$ARCH_OS_DISK"
sgdisk -o "$ARCH_OS_DISK"
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot --align-end "$ARCH_OS_DISK"

# The Recovery at the very end, as large as its image plus two MiB: the last
# sectors hold the backup table, and the root's end is aligned down to a MiB.
if [ "$ARCH_OS_RECOVERY_ENABLED" = "true" ]; then
    recovery_mib=$((($(stat -c %s "$(recovery_image)/recovery.img") + 1048575) / 1048576 + 2))
    sgdisk -n "2:0:-${recovery_mib}M" -t 2:8300 -c 2:root --align-end "$ARCH_OS_DISK"
    sgdisk -n 3:0:0 -t 3:8300 -c 3:recovery "$ARCH_OS_DISK"
else
    sgdisk -n 2:0:0 -t 2:8300 -c 2:root --align-end "$ARCH_OS_DISK"
fi
partprobe "$ARCH_OS_DISK"

# udev makes the new device nodes a moment after partprobe returns.
udevadm settle

# The new partitions start where the old ones did, and so do their signatures:
# a LUKS header left under a fresh btrfs is what mount then reads.
wipefs -af "$boot_part" "$system_part"

# The firmware's entries for partitions that are now gone. One left behind
# costs a line in a menu, so this is never fatal.
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

# The passphrase on stdin, never in an argument list /proc shows. Discards are
# let through and kept in the header, or fstrim trims nothing.
# https://wiki.archlinux.org/title/Dm-crypt/Specialties#Discard/TRIM_support_for_solid_state_drives_(SSD)
root_device="$system_part"
if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
    echo "encrypting ${system_part}"
    printf '%s' "$ARCH_OS_PASSWORD" | cryptsetup luksFormat "$system_part"
    printf '%s' "$ARCH_OS_PASSWORD" | cryptsetup open --allow-discards --persistent "$system_part" cryptroot
    root_device=/dev/mapper/cryptroot
fi

mkfs.fat -F 32 -n BOOT "$boot_part"
mkfs.btrfs -f -L BTRFS "$root_device"
mount -v -t btrfs "$root_device" "$MNT"
while read -r subvolume _; do
    btrfs subvolume create "${MNT}/${subvolume}"
done < <(btrfs_subvolumes)
umount -R "$MNT"

# @ first, since every other mount point is a directory inside it.
while IFS=$'\t' read -r subvolume path; do
    mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=${subvolume}" \
        "$root_device" "${MNT}${path%/}"
done < <(btrfs_subvolumes)

# A fresh subvolume is root's alone, and the installation writes to /var/tmp
# before systemd-tmpfiles could set it.
chmod 1777 "${MNT}/var/tmp"

# No copy-on-write for disk images, set on the empty folder so each inherits it.
# https://wiki.archlinux.org/title/Btrfs#Disabling_CoW
chattr +C "${MNT}/var/lib/libvirt/images"

# systemd would make subvolumes of these on first boot, noise in every listing.
mkdir -p "${MNT}/var/lib/portables" "${MNT}/var/lib/machines"

mount -v --mkdir -t vfat "$boot_part" "${MNT}/boot"

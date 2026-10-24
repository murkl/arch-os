# Layout and subvolumes: docs/REFERENCE.md
# https://wiki.archlinux.org/title/Installation_guide#Partition_the_disks

# An answer file from another machine may name any device, so the disk is
# checked against the selectable ones right before the write.
disks="$(options_disks | cut -f1)"
if ! grep -qxF "$ARCH_OS_DISK" <<<"$disks"; then
    echo "${ARCH_OS_DISK} is not one of the disks this machine can be installed on" >&2
    exit 10
fi
boot_part="$(boot_partition "$ARCH_OS_DISK")"
system_part="$(system_partition "$ARCH_OS_DISK")"

# Closes what an earlier attempt left mounted or open:
# docs/CONTRIBUTING.md#closing-the-target
swapoff -a || true
sync
unmount_target
if [ -e /dev/mapper/cryptroot ]; then
    cryptsetup close cryptroot
fi

# A held partition keeps the kernel from reading the new table. The ISO ships
# neither lvm2 nor mdadm, so no old volume group or array assembles by itself.
# lsblk -r joins two mount points of one partition with an escaped newline.
held="$(lsblk -nrpo NAME,TYPE,MOUNTPOINTS "$ARCH_OS_DISK" | awk -F'[ ]' '
    ($2 != "disk" && $2 != "part") || $3 != "" {
        gsub(/\\x0a/, ", ", $3)
        printf "%s %s%s", sep, $1, ($3 == "" ? "" : " at " $3); sep = ";"
    }')"
if [ -n "$held" ]; then
    echo "${ARCH_OS_DISK} is still in use:${held}" >&2
    exit 11
fi

# Read before the wipe: afterwards nothing tells which firmware entries pointed
# at this disk.
old_parts="$(lsblk -nro PARTUUID "$ARCH_OS_DISK" | awk 'NF { printf "%s ", tolower($1) }')"

wipefs -af "$ARCH_OS_DISK"
sgdisk --zap-all "$ARCH_OS_DISK"
sgdisk -o "$ARCH_OS_DISK"
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot --align-end "$ARCH_OS_DISK"

# 8304 is the x86-64 root type systemd finds the root by. The Recovery
# partition gets RECOVERY_MIB plus 2 MiB, since the backup GPT takes the last
# sectors.
if [ "$ARCH_OS_RECOVERY_ENABLED" = "true" ]; then
    sgdisk -n "2:0:-$((RECOVERY_MIB + 2))M" -t 2:8304 -c 2:root --align-end "$ARCH_OS_DISK"
    sgdisk -n 3:0:0 -t 3:8300 -c 3:recovery "$ARCH_OS_DISK"
else
    sgdisk -n 2:0:0 -t 2:8304 -c 2:root --align-end "$ARCH_OS_DISK"
fi
partprobe "$ARCH_OS_DISK"

# udev creates the device nodes shortly after partprobe returns.
udevadm settle

# Old signatures survive at the same offsets, and mount may read a stale LUKS
# header under the new btrfs. The Recovery image fills its partition only in
# part, and a leftover signature makes the UUID it is found by ambiguous.
parts=("$boot_part" "$system_part")
if [ "$ARCH_OS_RECOVERY_ENABLED" = "true" ]; then
    parts+=("$(recovery_partition "$ARCH_OS_DISK")")
fi
wipefs -af "${parts[@]}"

# Firmware entries of the wiped partitions. A leftover costs only a menu line,
# so this is never fatal.
# https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface#efibootmgr
if [ -n "$old_parts" ]; then
    if entries="$(efibootmgr)"; then
        while read -r entry; do
            echo "removing boot entry ${entry} of a wiped partition"
            efibootmgr -q -b "$entry" -B || echo "boot entry ${entry} could not be removed" >&2
        done < <(awk -v parts="$old_parts" '
            BEGIN { n = split(parts, part, " ") }
            /^Boot[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][* ]/ {
                line = tolower($0)
                for (i = 1; i <= n; i++) if (index(line, part[i])) { print substr($1, 5, 4); break }
            }' <<<"$entries")
    else
        echo "reading the firmware's boot entries failed, old ones stay listed" >&2
    fi
fi

# The passphrase on stdin, never in an argument /proc shows. --persistent keeps
# the options in the header for every later open: discards, or fstrim trims
# nothing, and on an SSD no dm-crypt workqueues.
# https://wiki.archlinux.org/title/Dm-crypt/Specialties#Discard/TRIM_support_for_solid_state_drives_(SSD)
# https://wiki.archlinux.org/title/Dm-crypt/Specialties#Disable_workqueue_for_increased_solid_state_drive_(SSD)_performance
root_device="$system_part"
if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
    passphrase="$ARCH_OS_PASSWORD"
    [ "$ARCH_OS_DISK_PASSWORD_ENABLED" = "true" ] && passphrase="$ARCH_OS_DISK_PASSWORD"
    open_options=(--allow-discards --persistent)
    if [ "$(lsblk -dnro ROTA "$ARCH_OS_DISK")" = "0" ]; then
        open_options+=(--perf-no_read_workqueue --perf-no_write_workqueue)
    fi
    echo "encrypting ${system_part}"
    printf '%s' "$passphrase" | cryptsetup -q luksFormat "$system_part"
    printf '%s' "$passphrase" | cryptsetup open "${open_options[@]}" "$system_part" cryptroot
    root_device=/dev/mapper/cryptroot
fi

mkfs.fat -F 32 -n BOOT "$boot_part"
mkfs.btrfs -f -L BTRFS "$root_device"
mount -v -t btrfs "$root_device" "$MNT"
while read -r subvolume _; do
    btrfs subvolume create "${MNT}/${subvolume}"
done < <(btrfs_subvolumes)
umount -R "$MNT"

# @ first: every other mount point lies inside it.
while IFS=$'\t' read -r subvolume path; do
    mount --mkdir -t btrfs -o "${BTRFS_OPTS},subvol=${subvolume}" \
        "$root_device" "${MNT}${path%/}"
done < <(btrfs_subvolumes)

# A new subvolume is writable by root only, and the installation writes to
# /var/tmp before systemd-tmpfiles runs.
chmod 1777 "${MNT}/var/tmp"

# Otherwise systemd creates them as subvolumes on first boot, clutter in every
# listing.
mkdir -p "${MNT}/var/lib/portables" "${MNT}/var/lib/machines"

# Root only, since it holds the kernel and the signed images. genfstab copies
# these mount options.
mount -v --mkdir -t vfat -o fmask=0077,dmask=0077 "$boot_part" "${MNT}/boot"

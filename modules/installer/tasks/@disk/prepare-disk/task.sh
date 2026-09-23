# Partition, encrypt, format and mount the target. The only stage that destroys
# data: everything before it is reversible by walking away.
# https://wiki.archlinux.org/title/Installation_guide#Partition_the_disks
#
# The layout and the subvolumes: docs/REFERENCE.md

# A dual boot writes its kernel into an EFI partition somebody else made, and
# Windows makes that one 100 or 260 MB. What goes in needs more: the kernel,
# its ram disk, and the fallback ram disk that carries every module there is -
# and where the boot chain is signed, the kernel is packed into both of them
# again. Asked here, because the same question answered where the images are
# built is answered on a disk this run has already formatted.
#
# Mounted read-only to ask it, and a partition that will not mount is not
# refused: it is the other system's, and being unable to read it says nothing
# about how much room is on it.
if [ "$ARCH_OS_DUAL_BOOT_ENABLED" = "true" ]; then
    needed=$((512 * 1024 * 1024))
    probe="$(mktemp -d)"
    free=""
    kernels=""
    if mount -o ro "$ARCH_OS_BOOT_PARTITION" "$probe" 2>/dev/null; then
        free="$(df -B1 --output=avail "$probe" | tail -n1)"
        kernels="$(find "$probe" -maxdepth 1 \( -name 'vmlinuz-*' -o -name 'initramfs-*' -o -name '*-ucode.img' \) -printf '%f ')"
        umount "$probe"
    fi
    rmdir "$probe"

    # Boot images already there belong to the other system, and this one writes
    # its own under the same names. pacman sees a file no package of the new
    # root owns and refuses the whole transaction - the right answer, arriving
    # as "conflicting files" an hour in, after the disk has been written. The
    # systems dual boot is meant for keep their boot files to themselves, which
    # is what Windows does.
    if [ -n "$kernels" ]; then
        echo "${ARCH_OS_BOOT_PARTITION} already holds another Linux system's boot images: ${kernels}- two systems cannot keep theirs in one EFI partition, and this installation would write over them. Install without dual boot, or move that system's boot images somewhere of its own." >&2
        exit 1
    fi

    if [ -z "$free" ]; then
        echo "${ARCH_OS_BOOT_PARTITION} could not be mounted, so what is on it and how much room is left is unknown" >&2
    elif [ "$free" -lt "$needed" ]; then
        echo "${ARCH_OS_BOOT_PARTITION} has $(numfmt --to=iec "$free") free and the boot images need about $(numfmt --to=iec "$needed"). Make that EFI partition bigger, or free space on it, and start again." >&2
        exit 1
    fi
fi

# Dual boot keeps the disk as it is: the other system's partitions, its EFI
# partition and its boot entries all stay.
if [ "$ARCH_OS_DUAL_BOOT_ENABLED" != "true" ]; then
    wipefs -af "$ARCH_OS_DISK"
    sgdisk --zap-all "$ARCH_OS_DISK"
    sgdisk -o "$ARCH_OS_DISK"
    sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot --align-end "$ARCH_OS_DISK"
    sgdisk -n 2:0:0 -t 2:8300 -c 2:root --align-end "$ARCH_OS_DISK"
    partprobe "$ARCH_OS_DISK"

    # partprobe tells the kernel to re-read the table; the device nodes under
    # it are udev's, and it makes them a moment later. Without the wait the
    # format below runs against a path that is not there yet.
    udevadm settle
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

mount -v --mkdir "$ARCH_OS_BOOT_PARTITION" "${MNT}/boot"

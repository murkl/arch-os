# Install the packages the system is made of, and write the file system table.

simulating && return 0

# sudo is named outright: it comes with base-devel, which only an installation
# that builds from the AUR needs — and the wheel rule is written either way.
packages=("$ARCH_OS_KERNEL" base sudo linux-firmware wireless-regdb zram-generator networkmanager)

[ "$ARCH_OS_MICROCODE" != "none" ] && packages+=("$ARCH_OS_MICROCODE")
[ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && packages+=(btrfs-progs)
[ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && [ "$ARCH_OS_BTRFS_SNAPPER_ENABLED" = "true" ] && packages+=(snapper)
secure_boot_wanted && packages+=(sbctl)

# grub-install writes the firmware boot entry through efibootmgr; bootctl talks
# to efivarfs itself and needs neither. grub-btrfsd watches the snapshot
# directory with inotify.
if [ "$ARCH_OS_BOOTLOADER" = "grub" ]; then
    packages+=(grub efibootmgr)
    [ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && packages+=(grub-btrfs inotify-tools)
    # Finds the other system so GRUB can offer it.
    [ "$ARCH_OS_DUAL_BOOT_ENABLED" = "true" ] && packages+=(os-prober)
fi

# Before the packages, because installing the kernel builds a ram disk, and the
# hook that puts a keyboard layout in it reads this file — see write_vconsole.
write_vconsole

# Retried, and with the download timeout off: this is the longest download of
# the installation and the one most likely to meet a slow mirror.
installed=false
for ((i = 1; i <= RETRIES; i++)); do
    [ "$i" -gt 1 ] && echo "retry ${i}/${RETRIES}: pacstrap"
    if pacstrap -K "$MNT" "${packages[@]}" --disable-download-timeout; then
        installed=true
        break
    fi
    sleep "$RETRY_WAIT"
done
if [ "$installed" != "true" ]; then
    echo "installing the base system failed after ${RETRIES} attempts" >&2
    exit 1
fi

genfstab -U "$MNT" >>"${MNT}/etc/fstab"

# The EFI partition holds the kernel and, with Secure Boot, the signed image.
# Neither is anyone's business but root's.
sed -i '/\/boot/ {s/fmask=[0-9]\+/fmask=0077/g; s/dmask=[0-9]\+/dmask=0077/g}' "${MNT}/etc/fstab"

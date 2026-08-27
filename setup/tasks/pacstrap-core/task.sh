# Install the packages the system is made of, and write the file system table.

simulating && return 0

packages=("$ARCH_OS_KERNEL" base base-devel linux-firmware zram-generator networkmanager)

[ "$ARCH_OS_MICROCODE" != "none" ] && packages+=("$ARCH_OS_MICROCODE")
[ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && packages+=(btrfs-progs efibootmgr inotify-tools)
[ "$ARCH_OS_BOOTLOADER" = "grub" ] && packages+=(grub grub-btrfs)

# os-prober is what finds the other system so GRUB can offer it.
[ "$ARCH_OS_BOOTLOADER" = "grub" ] && [ "$ARCH_OS_DUAL_BOOT_ENABLED" = "true" ] && packages+=(os-prober)
[ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && [ "$ARCH_OS_BTRFS_SNAPPER_ENABLED" = "true" ] && packages+=(snapper)
secure_boot_wanted && packages+=(sbctl)

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

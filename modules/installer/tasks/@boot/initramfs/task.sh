# The images the firmware starts: the initial ram disk, or - where the boot chain
# is signed - the unified kernel image that replaces it.
#
# Before the boot loader, because both loaders point at what this leaves behind,
# and after the base system, because building a ram disk is mkinitcpio running
# inside the installed one. Why these hooks and in this order: docs/REFERENCE.md
# https://wiki.archlinux.org/title/Mkinitcpio#Common_hooks

simulating && return 0

btrfs_hook=""
[ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && [ "$ARCH_OS_BOOTLOADER" = "grub" ] && btrfs_hook=" grub-btrfs-overlayfs"

encrypt_hook=""
[ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && encrypt_hook=" sd-encrypt"

hooks="base systemd keyboard autodetect microcode modconf kms sd-vconsole block${encrypt_hook} filesystems fsck${btrfs_hook}"

# As a drop-in: mkinitcpio reads its own file first and every drop-in after it
# in name order, so the boot splash (20-) and the graphics driver (30-) build on
# this one.
mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
{
    echo '# Written by the Arch OS Installer.'
    echo "HOOKS=(${hooks})"
} >"${MNT}/etc/mkinitcpio.conf.d/10-arch-os.conf"

# A unified kernel image packs kernel, ram disk and command line into one EFI
# binary that is signed as a whole.
if secure_boot_wanted; then
    # The command line moves into the image, so it has to exist first: without
    # this file mkinitcpio falls back to /proc/cmdline, which inside the chroot
    # is the live image's.
    mkdir -p "${MNT}/etc/kernel"
    kernel_args >"${MNT}/etc/kernel/cmdline"

    # Written whole rather than patched: mkinitcpio creates a preset from a
    # template only when it is missing, so this file is ours from here on.
    {
        echo "# Written by the Arch OS Installer: a signed unified kernel image"
        echo "# instead of a bare initramfs, for Secure Boot."
        echo "ALL_kver=\"/boot/vmlinuz-${ARCH_OS_KERNEL}\""
        # Named outright: mkinitcpio's last resort is /proc/cmdline.
        echo "ALL_cmdline=\"/etc/kernel/cmdline\""
        echo "PRESETS=('default' 'fallback')"
        echo "default_uki=\"/boot/EFI/Linux/arch-${ARCH_OS_KERNEL}.efi\""
        echo "fallback_uki=\"/boot/EFI/Linux/arch-${ARCH_OS_KERNEL}-fallback.efi\""
        echo "fallback_options=\"-S autodetect\""
    } >"${MNT}/etc/mkinitcpio.d/${ARCH_OS_KERNEL}.preset"
    mkdir -p "${MNT}/boot/EFI/Linux"
fi

arch-chroot "$MNT" mkinitcpio -P

# Installing the kernel already built a pair of plain ram disks from the preset
# the package ships. With the preset above they are never written again, and an
# initramfs nothing updates is what the unified image does away with.
if secure_boot_wanted; then
    rm -f "${MNT}/boot/initramfs-${ARCH_OS_KERNEL}.img" "${MNT}/boot/initramfs-${ARCH_OS_KERNEL}-fallback.img"
fi

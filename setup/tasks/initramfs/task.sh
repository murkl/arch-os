# The initial ram disk, and — where the boot chain is signed — the unified
# kernel image that replaces it.

simulating && return 0

# https://wiki.archlinux.org/title/Mkinitcpio#Common_hooks
btrfs_hook=""
[ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && [ "$ARCH_OS_BOOTLOADER" = "grub" ] && btrfs_hook=" grub-btrfs-overlayfs"

hooks="base systemd keyboard autodetect microcode modconf sd-vconsole block filesystems fsck${btrfs_hook}"
[ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] &&
    hooks="base systemd keyboard autodetect microcode modconf sd-vconsole block sd-encrypt filesystems fsck${btrfs_hook}"
sed -i "s/^HOOKS=(.*)$/HOOKS=(${hooks})/" "${MNT}/etc/mkinitcpio.conf"

# A unified kernel image packs kernel, ram disk and command line into one EFI
# binary that can be signed as a whole. Without it the ram disk would sit
# unsigned on the one partition that is never encrypted — and a forged ram disk
# collects the passphrase, which is exactly what signing is meant to prevent.
if secure_boot_wanted; then
    # The command line moves into the image, so it has to exist before mkinitcpio
    # runs: without this file mkinitcpio falls back to /proc/cmdline, which
    # inside the chroot is the live image's command line.
    mkdir -p "${MNT}/etc/kernel"
    kernel_args >"${MNT}/etc/kernel/cmdline"

    # Written whole rather than patched: the preset belongs to no package —
    # mkinitcpio creates it from a template only when it is missing — so this
    # file is ours and survives every kernel update untouched.
    {
        echo "# Written by the Arch OS Installer: a signed unified kernel image"
        echo "# instead of a bare initramfs, for Secure Boot."
        echo "ALL_kver=\"/boot/vmlinuz-${ARCH_OS_KERNEL}\""
        # Named outright rather than left to mkinitcpio's lookup order, whose
        # last resort is /proc/cmdline.
        echo "ALL_cmdline=\"/etc/kernel/cmdline\""
        echo "PRESETS=('default' 'fallback')"
        echo "default_uki=\"/boot/EFI/Linux/arch-${ARCH_OS_KERNEL}.efi\""
        echo "fallback_uki=\"/boot/EFI/Linux/arch-${ARCH_OS_KERNEL}-fallback.efi\""
        echo "fallback_options=\"-S autodetect\""
    } >"${MNT}/etc/mkinitcpio.d/${ARCH_OS_KERNEL}.preset"
    mkdir -p "${MNT}/boot/EFI/Linux"
fi

arch-chroot "$MNT" mkinitcpio -P

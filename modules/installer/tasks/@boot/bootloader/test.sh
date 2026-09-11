# A machine that will not boot is the one failure nothing later can make up for,
# so what is checked is the two files the firmware actually reaches for: the
# image the kernel is in, and the loader that starts it.
debugging && return 0

if secure_boot_wanted; then
    [ -f "${MNT}/boot/EFI/Linux/arch-${ARCH_OS_KERNEL}.efi" ]
else
    [ -f "${MNT}/boot/initramfs-${ARCH_OS_KERNEL}.img" ]
fi

if [ "$ARCH_OS_BOOTLOADER" = "grub" ]; then
    [ -f "${MNT}/boot/grub/grub.cfg" ]
else
    arch-chroot "$MNT" bootctl --esp-path=/boot is-installed | grep -qx yes
fi

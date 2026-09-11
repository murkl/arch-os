# A machine that will not boot is the one failure nothing later can make up for,
# so what is checked is what the firmware actually reaches for: both images the
# kernel is in, and the loader that starts them.
debugging && return 0

while read -r image; do
    [ -f "${MNT}${image}" ]
done < <(boot_images)

if [ "$ARCH_OS_BOOTLOADER" = "grub" ]; then
    [ -f "${MNT}/boot/grub/grub.cfg" ]
else
    arch-chroot "$MNT" bootctl --esp-path=/boot is-installed | grep -qx yes
fi

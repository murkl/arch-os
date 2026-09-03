# Show a logo while the system starts instead of a wall of kernel messages.

simulating && return 0

chroot_pacman_install plymouth git base-devel

# The hook goes directly behind the init hook, which is early enough to have a
# screen to draw on. mkinitcpio concatenates its own configuration and every
# drop-in and sources the lot as one file, so this splices the array the
# initramfs task already set rather than matching a line with a pattern.
mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
{
    echo '# Written by the Arch OS Installer.'
    # shellcheck disable=SC2016  # mkinitcpio expands this, not us
    echo 'HOOKS=("${HOOKS[@]:0:2}" plymouth "${HOOKS[@]:2}")'
} >"${MNT}/etc/mkinitcpio.conf.d/20-plymouth.conf"

chroot_aur_install plymouth-theme-arch-os

# Split rather than done with `plymouth-set-default-theme -R`: that command ends
# on `exit 0` whatever mkinitcpio made of the rebuild.
arch-chroot "$MNT" plymouth-set-default-theme arch-os
arch-chroot "$MNT" mkinitcpio -P

# And what was built rather than what was asked for: plymouth's build hook says
# so and gives up when it cannot find the theme's plugin or font, and mkinitcpio
# finishes the image without it. That image boots perfectly well, without a
# splash.
#
# What it built is a signed unified image where the boot chain is signed, and a
# bare ram disk where it is not.
if secure_boot_wanted; then
    images=("/boot/EFI/Linux/arch-${ARCH_OS_KERNEL}.efi" "/boot/EFI/Linux/arch-${ARCH_OS_KERNEL}-fallback.efi")
else
    images=("/boot/initramfs-${ARCH_OS_KERNEL}.img" "/boot/initramfs-${ARCH_OS_KERNEL}-fallback.img")
fi

for image in "${images[@]}"; do
    if ! arch-chroot "$MNT" lsinitcpio "$image" | grep -q 'plymouthd'; then
        echo "plymouth is missing from ${image}" >&2
        exit 1
    fi
done

# A logo while the system starts instead of a wall of kernel messages.
# https://wiki.archlinux.org/title/Plymouth

chroot_pacman_install plymouth

# Directly behind the init hook, which is early enough to have a screen to draw
# on. mkinitcpio sources its own file and every drop-in as one, so this splices
# the array the initramfs task set rather than matching a line with a pattern.
mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
render "$(where)/20-plymouth.conf" >"${MNT}/etc/mkinitcpio.conf.d/20-plymouth.conf"

chroot_aur_install plymouth-theme-arch-os

# Split rather than `plymouth-set-default-theme -R`, which ends on `exit 0`
# whatever mkinitcpio made of the rebuild.
arch-chroot "$MNT" plymouth-set-default-theme arch-os
arch-chroot "$MNT" mkinitcpio -P

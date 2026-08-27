# Show a logo while the system starts instead of a wall of kernel messages.

simulating && return 0

chroot_pacman_install plymouth git base-devel

# The hook has to run early enough to have a screen to draw on, which is
# directly after the console keyboard is set up.
sed -i "s/base systemd keyboard/base systemd plymouth keyboard/g" "${MNT}/etc/mkinitcpio.conf"

chroot_aur_install plymouth-theme-arch-os

# -R rebuilds the ram disk, which is what actually puts the theme in it.
arch-chroot "$MNT" plymouth-set-default-theme -R arch-os

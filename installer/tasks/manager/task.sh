# The menu entry comes from the manager-app task. checkupdates needs fakeroot,
# which pacman-contrib only suggests. https://github.com/murkl/arch-os-manager
chroot_pacman_install pacman-contrib fakeroot
chroot_aur_install arch-os-manager

# A menu for updating, cleaning up and repairing the system afterwards. Its
# place among the applications comes with the desktop: manager-app. It lists
# the updates with checkupdates, which needs fakeroot that pacman-contrib only
# suggests. https://github.com/murkl/arch-os-manager
chroot_pacman_install pacman-contrib fakeroot
chroot_aur_install arch-os-manager

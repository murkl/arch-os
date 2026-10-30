# Before every task that installs lib32 packages.
# https://wiki.archlinux.org/title/Official_repositories#multilib
pacman_include "$(where)/arch-os-multilib.conf"
chroot_pacman_install -yu

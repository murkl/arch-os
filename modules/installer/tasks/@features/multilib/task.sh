# Before anything that pulls lib32 packages. A file pacman.conf includes - see
# pacman_include in module.sh.
# https://wiki.archlinux.org/title/Official_repositories#multilib
pacman_include "$(where)/arch-os-multilib.conf"
arch-chroot "$MNT" pacman -Syu --noconfirm

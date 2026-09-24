# Switched on before anything that needs it is installed: the desktop and the
# graphics driver both pull lib32 packages. The repository is a file of its own
# that pacman.conf includes - see pacman_include in module.sh.
# https://wiki.archlinux.org/title/Official_repositories#multilib

pacman_include "$(where)/arch-os-multilib.conf"
arch-chroot "$MNT" pacman -Syu --noconfirm

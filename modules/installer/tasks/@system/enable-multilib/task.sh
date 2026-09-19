# Switched on before anything that needs it is installed: the desktop and the
# graphics driver both pull lib32 packages. A repository is a section of
# pacman.conf and pacman reads no drop-in directory, so this is an edit.
# https://wiki.archlinux.org/title/Official_repositories#multilib

simulating && return 0

sed -i '/\[multilib\]/,/Include/s/^#//' "${MNT}/etc/pacman.conf"
arch-chroot "$MNT" pacman -Syu --noconfirm

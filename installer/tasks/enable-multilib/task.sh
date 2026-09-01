# Switch on the 32-bit repository.
#
# Before anything that needs it is installed, which is why this stage sits where
# it does: the desktop and the graphics driver both pull lib32 packages, and a
# repository switched on afterwards would come too late for them.

simulating && return 0

sed -i '/\[multilib\]/,/Include/s/^#//' "${MNT}/etc/pacman.conf"
arch-chroot "$MNT" pacman -Syyu --noconfirm

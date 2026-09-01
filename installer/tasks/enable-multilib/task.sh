# Switch on the 32-bit repository, before anything that needs it is installed:
# the desktop and the graphics driver both pull lib32 packages.

simulating && return 0

# In pacman.conf itself, because a repository is a section of that file and
# pacman reads no drop-in directory. The section is already there, commented out.
sed -i '/\[multilib\]/,/Include/s/^#//' "${MNT}/etc/pacman.conf"
arch-chroot "$MNT" pacman -Syu --noconfirm

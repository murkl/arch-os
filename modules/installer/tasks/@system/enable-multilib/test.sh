# The repository answers, which is more than the section being uncommented.
debugging && return 0

arch-chroot "$MNT" pacman -Sl multilib >/dev/null

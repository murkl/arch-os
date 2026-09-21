# Nothing is left that nothing asked for: a removal that half worked leaves
# exactly this list.
simulating && return 0

! arch-chroot "$MNT" pacman -Qtdq >/dev/null 2>&1

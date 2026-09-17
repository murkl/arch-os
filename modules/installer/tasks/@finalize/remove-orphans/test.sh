# Nothing is left that nothing asked for. The one thing worth reading back here
# is the state itself: a removal that half worked leaves exactly this list.
debugging && return 0

! arch-chroot "$MNT" pacman -Qtdq >/dev/null 2>&1

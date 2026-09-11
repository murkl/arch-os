# paru-bin and paru-git install the same command as paru does.
debugging && return 0

arch-chroot "$MNT" command -v "${ARCH_OS_AUR_HELPER%%-*}" >/dev/null

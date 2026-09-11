# paru-bin and paru-git install the same command as paru does.
arch-chroot "$MNT" command -v "${ARCH_OS_AUR_HELPER%%-*}" >/dev/null

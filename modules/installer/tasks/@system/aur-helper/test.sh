# paru-bin and paru-git install the same command as paru does.
debugging && return 0

has_command "${ARCH_OS_AUR_HELPER%%-*}"

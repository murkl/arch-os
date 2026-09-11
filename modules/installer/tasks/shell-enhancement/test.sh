# Every shell gets the prompt through .bashrc; zsh additionally becomes the one
# that opens.
[ -f "${MNT}/home/${ARCH_OS_USERNAME}/.bashrc" ]
[ "$ARCH_OS_SHELL_ENHANCEMENT_SHELL" != "zsh" ] ||
    arch-chroot "$MNT" getent passwd "$ARCH_OS_USERNAME" | grep -q ':/usr/bin/zsh$'

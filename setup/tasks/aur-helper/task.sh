# Build the AUR helper from source, which is the only way it can be installed.

simulating && return 0

chroot_pacman_install git base-devel
chroot_aur_install "$ARCH_OS_AUR_HELPER"

# paru shows the newest results last, next to the prompt, and asks for the sudo
# password once for a whole batch of builds rather than once per package.
case "$ARCH_OS_AUR_HELPER" in
paru | paru-bin | paru-git)
    sed -i 's/^#BottomUp/BottomUp/g' "${MNT}/etc/paru.conf"
    sed -i 's/^#SudoLoop/SudoLoop/g' "${MNT}/etc/paru.conf"
    ;;
esac

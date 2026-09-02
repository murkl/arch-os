# Build the AUR helper from source, which is the only way it can be installed.

simulating && return 0

chroot_pacman_install git base-devel
chroot_aur_install "$ARCH_OS_AUR_HELPER"

# paru shows the newest results last, next to the prompt, and asks for the sudo
# password once for a whole batch of builds rather than once per package.
#
# Written to the user's own configuration, not /etc/paru.conf: that file
# belongs to the paru package, so editing it would leave a .pacnew to merge on
# every paru update. And how one person likes to be asked for a password is
# theirs to change, not the system's.
case "$ARCH_OS_AUR_HELPER" in
paru | paru-bin | paru-git)
    config="${MNT}/home/${ARCH_OS_USERNAME}/.config/paru"
    mkdir -p "$config"
    {
        echo '# Written by the Arch OS Installer. Yours to change.'
        echo '#'
        echo '# paru reads the first configuration it finds and stops, so this one stands'
        echo '# in place of /etc/paru.conf rather than adding to it, which is why the'
        echo "# package's own defaults are repeated here."
        echo '# See paru.conf(5).'
        echo
        echo '[options]'
        echo 'PgpFetch'
        echo 'Devel'
        echo 'Provides'
        echo 'DevelSuffixes = -git -cvs -svn -bzr -darcs -always -hg -fossil'
        echo
        echo '# The newest results last, next to the prompt.'
        echo 'BottomUp'
        echo '# One password for a whole batch of builds, not one per package.'
        echo 'SudoLoop'
    } >"${config}/paru.conf"
    arch-chroot "$MNT" chown -R "${ARCH_OS_USERNAME}:${ARCH_OS_USERNAME}" "/home/${ARCH_OS_USERNAME}/.config"
    ;;
esac

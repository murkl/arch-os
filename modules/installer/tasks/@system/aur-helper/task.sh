# The AUR helper, built the way everything from the AUR is built - see
# chroot_aur_install in module.sh. https://wiki.archlinux.org/title/AUR_helpers

simulating && return 0

chroot_aur_install "$ARCH_OS_AUR_HELPER"

# Written to the user's own configuration rather than /etc/paru.conf: how one
# person likes to be asked for a password is theirs to change. yay has no
# per-user config file to write.
if [ "$ARCH_OS_AUR_HELPER" = "paru" ]; then
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
    own_home
fi

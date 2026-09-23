# The AUR helper, built the way everything from the AUR is built - see
# chroot_aur_install in module.sh. https://wiki.archlinux.org/title/AUR_helpers

chroot_aur_install "$ARCH_OS_AUR_HELPER"

# Written to the user's own configuration rather than /etc/paru.conf: how one
# person likes to be asked for a password is theirs to change. yay has no
# per-user config file to write.
if [ "$ARCH_OS_AUR_HELPER" = "paru" ]; then
    config="${MNT}/home/${ARCH_OS_USERNAME}/.config/paru"
    mkdir -p "$config"
    render "$(where)/paru.conf" >"${config}/paru.conf"
    own_home
fi

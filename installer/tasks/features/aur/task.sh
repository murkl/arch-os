# Built the way everything from the AUR is, see chroot_aur_install in lib.sh.
# https://wiki.archlinux.org/title/AUR_helpers
chroot_aur_install paru

# The user's own configuration: how one person is asked for a password is theirs.
config="$(user_home)/.config/paru"
mkdir -p "$config"
render "$(where)/paru.conf" >"${config}/paru.conf"
own_home

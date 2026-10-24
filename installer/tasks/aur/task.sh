# https://wiki.archlinux.org/title/AUR_helpers
chroot_aur_install paru

# In the account's home, since password prompts are a personal choice.
config="$(user_home)/.config/paru"
mkdir -p "$config"
render "$(where)/paru.conf" >"${config}/paru.conf"
own_home

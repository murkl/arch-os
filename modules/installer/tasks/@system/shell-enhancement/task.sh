# A terminal that is pleasant on the first login. Everything it writes is a file
# beside this one, copied into place.

simulating && return 0

home="${MNT}/home/${ARCH_OS_USERNAME}"
data="$(where)"

packages=(git starship eza bat zoxide fd fzf fastfetch mc btop
    bash-completion nano-syntax-highlighting ttf-firacode-nerd)
chroot_pacman_install "${packages[@]}"

mkdir -p "${MNT}/root/.config/fastfetch" "${home}/.config/fastfetch"

# ----------------------------------------------------------------------------

# For both root and the user: it is the same shell either way. An AUR helper
# covers both repositories and asks for the password itself, where pacman needs
# sudo.
pkg="pacman"
sudo_prefix="sudo "
if [ "$ARCH_OS_AUR_HELPER" != "none" ]; then
    pkg="$ARCH_OS_AUR_HELPER"
    sudo_prefix=""
fi

sed -e "s|{{PKG}}|${pkg}|g" -e "s|{{SUDO}}|${sudo_prefix}|g" "${data}/aliases" |
    tee "${MNT}/root/.aliases" "${home}/.aliases" >/dev/null

# ----------------------------------------------------------------------------

# bash is always configured: it is the shell every task and hook runs in. zsh
# becomes the login shell outright; fish cannot, because it is not a POSIX shell
# and a login shell that cannot read a POSIX profile breaks things well outside
# the terminal - so .bashrc hands over to it instead.
shell="$ARCH_OS_SHELL_ENHANCEMENT_SHELL"

# The handover read in where the marker stands, and the marker line dropped -
# sed, like the two placeholders above, rather than a bash substitution. That
# is the wrong tool twice over here: a pattern whose first character is a # is
# read as an anchor to the start of the string and matches nothing, and an &
# in the replacement stands for whatever matched, which a line full of && then
# tears apart. Both went unnoticed because the first hid the second.
#
# Empty for the other two shells, so the marker line simply goes.
handover="$(mktemp)"
[ "$shell" = "fish" ] && sed "s|{{SHELL}}|${shell}|g" "${data}/shell-handover" >"$handover"

sed -e "/{{SHELL_HANDOVER}}/r ${handover}" -e "/{{SHELL_HANDOVER}}/d" "${data}/bashrc" |
    tee "${MNT}/root/.bashrc" "${home}/.bashrc" >/dev/null
rm -f "$handover"

tee "${MNT}/root/.config/fastfetch/config.jsonc" "${home}/.config/fastfetch/config.jsonc" <"${data}/fastfetch.jsonc" >/dev/null

case "$shell" in
zsh)
    chroot_pacman_install zsh zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search
    tee "${MNT}/root/.zshrc" "${home}/.zshrc" <"${data}/zshrc" >/dev/null
    # /etc/shells already lists it, which is what chsh checks against.
    arch-chroot "$MNT" chsh -s /usr/bin/zsh root
    arch-chroot "$MNT" chsh -s /usr/bin/zsh "$ARCH_OS_USERNAME"
    ;;
fish)
    chroot_pacman_install fish
    mkdir -p "${MNT}/root/.config/fish" "${home}/.config/fish"
    tee "${MNT}/root/.config/fish/config.fish" "${home}/.config/fish/config.fish" <"${data}/config.fish" >/dev/null
    ;;
esac

# ----------------------------------------------------------------------------

# Fetched rather than shipped, so it can be improved without a new release of
# this installer. A machine that cannot reach it gets a starship preset.
mkdir -p "${MNT}/root/.config"
if ! curl -Lf --connect-timeout 5 --max-time 30 \
    https://raw.githubusercontent.com/murkl/starship-theme-arch-os/refs/heads/main/starship.toml \
    >"${home}/.config/starship.toml" || [ ! -s "${home}/.config/starship.toml" ]; then
    echo "the Arch OS prompt theme could not be fetched, falling back to a built-in one"
    arch-chroot "$MNT" /usr/bin/starship preset pure-preset -o "/home/${ARCH_OS_USERNAME}/.config/starship.toml"
fi
cp "${home}/.config/starship.toml" "${MNT}/root/.config/starship.toml"

# ----------------------------------------------------------------------------

# nanorc goes into each home rather than /etc/nanorc, which belongs to the
# nano package and would leave a .pacnew to merge on every update.
mkdir -p "${MNT}/root/.config/nano" "${home}/.config/nano"
tee "${MNT}/root/.config/nano/nanorc" "${home}/.config/nano/nanorc" <"${data}/nanorc" >/dev/null

# ----------------------------------------------------------------------------

# Settings only reachable once a session exists.
if [ "$ARCH_OS_DESKTOP" != "none" ]; then
    on_first_login <<'FIRST'
# The terminal font, which has to match the one the prompt draws with.
gsettings set org.gnome.desktop.interface monospace-font-name 'FiraCode Nerd Font 11'
FIRST
fi

if [ "$shell" = "fish" ] && [ "$ARCH_OS_DESKTOP" != "none" ]; then
    on_first_login <<'FIRST'
fish -c 'fish_config theme choose Nord && echo y | fish_config theme save'
FIRST
fi

own_home

# A terminal that is pleasant on the first login. Everything it writes is a file
# beside this one, put in place through render.

home="${MNT}/home/${ARCH_OS_USERNAME}"
data="$(where)"

packages=(git starship eza bat zoxide fd fzf fastfetch mc btop bash-completion ttf-firacode-nerd
    zsh zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search)
chroot_pacman_install "${packages[@]}"

mkdir -p "${MNT}/root/.config/fastfetch" "${home}/.config/fastfetch"

# For both root and the user: it is the same shell either way. bash is set up
# as well as zsh, because it is the shell every task and hook runs in and the
# one a script started by hand reaches for.
for file in aliases bashrc zshrc; do
    render "${data}/${file}" | tee "${MNT}/root/.${file}" "${home}/.${file}" >/dev/null
done
render "${data}/fastfetch.jsonc" | tee "${MNT}/root/.config/fastfetch/config.jsonc" "${home}/.config/fastfetch/config.jsonc" >/dev/null

# /etc/shells already lists it, which is what chsh checks against.
arch-chroot "$MNT" chsh -s /usr/bin/zsh root
arch-chroot "$MNT" chsh -s /usr/bin/zsh "$ARCH_OS_USERNAME"

# ----------------------------------------------------------------------------

# Fetched rather than shipped, so it can be improved without a new release of
# this installer. A machine that cannot reach it gets a starship preset.
mkdir -p "${MNT}/root/.config"
if ! fetch_url --connect-timeout 5 --max-time 30 \
    https://raw.githubusercontent.com/murkl/starship-theme-arch-os/refs/heads/main/starship.toml \
    >"${home}/.config/starship.toml" || [ ! -s "${home}/.config/starship.toml" ]; then
    echo "the Arch OS prompt theme could not be fetched, falling back to a built-in one"
    arch-chroot "$MNT" /usr/bin/starship preset pure-preset -o "/home/${ARCH_OS_USERNAME}/.config/starship.toml"
fi
cp "${home}/.config/starship.toml" "${MNT}/root/.config/starship.toml"

# ----------------------------------------------------------------------------

# Only for nano: the highlighting depends on it and would bring it back onto a
# machine whose editor is another one. nanorc goes into each home rather than
# /etc/nanorc, which belongs to the nano package and would leave a .pacnew to
# merge on every update.
if [ "$ARCH_OS_EDITOR" = "nano" ]; then
    chroot_pacman_install nano-syntax-highlighting
    mkdir -p "${MNT}/root/.config/nano" "${home}/.config/nano"
    render "${data}/nanorc" | tee "${MNT}/root/.config/nano/nanorc" "${home}/.config/nano/nanorc" >/dev/null
fi

# ----------------------------------------------------------------------------

# Settings only reachable once a session exists.
if [ "$ARCH_OS_DESKTOP" != "none" ]; then
    on_first_login <<'FIRST'
# The terminal font, which has to match the one the prompt draws with.
gsettings set org.gnome.desktop.interface monospace-font-name 'FiraCode Nerd Font 11'
FIRST
fi

own_home

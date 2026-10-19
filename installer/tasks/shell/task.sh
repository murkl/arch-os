# A terminal that is pleasant on the first login.

home="$(user_home)"
data="$(where)"

packages=(git starship eza bat zoxide fd fzf fastfetch mc btop bash-completion
    zsh zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search)

# The font the prompt's glyphs are drawn in, by a terminal in a window. The text
# console draws none of them, see data/bashrc.
[ "$ARCH_OS_DESKTOP" != "none" ] && packages+=(ttf-firacode-nerd)
chroot_pacman_install "${packages[@]}"

mkdir -p "${MNT}/root/.config/fastfetch" "${home}/.config/fastfetch"

# bash for both, zsh for the account only: the emergency shell of a broken boot
# should not depend on zsh and its plugins.
for file in aliases bashrc; do
    render "${data}/${file}" | tee "${MNT}/root/.${file}" "${home}/.${file}" >/dev/null
done
render "${data}/zshrc" >"${home}/.zshrc"
render "${data}/fastfetch.jsonc" | tee "${MNT}/root/.config/fastfetch/config.jsonc" "${home}/.config/fastfetch/config.jsonc" >/dev/null
arch-chroot "$MNT" chsh -s /usr/bin/zsh "$ARCH_OS_USERNAME"

# Fetched, so the prompt can improve without a release, a preset otherwise.
mkdir -p "${MNT}/root/.config"
if ! fetch_url --connect-timeout 5 --max-time 30 \
    https://raw.githubusercontent.com/murkl/starship-theme-arch-os/refs/heads/main/starship.toml \
    >"${home}/.config/starship.toml" || [ ! -s "${home}/.config/starship.toml" ]; then
    echo "the Arch OS prompt theme could not be fetched, falling back to a built-in one"
    arch-chroot "$MNT" /usr/bin/starship preset pure-preset -o "/home/${ARCH_OS_USERNAME}/.config/starship.toml"
fi
cp "${home}/.config/starship.toml" "${MNT}/root/.config/starship.toml"

own_home

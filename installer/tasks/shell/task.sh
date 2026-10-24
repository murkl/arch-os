home="$(user_home)"
data="$(where)"

packages=(git starship eza bat zoxide fd fzf fastfetch mc btop bash-completion
    zsh zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search)

# The prompt's glyphs for a terminal in a window. The text console has none,
# see data/bashrc.
[ "$ARCH_OS_DESKTOP" != "none" ] && packages+=(ttf-firacode-nerd)
chroot_pacman_install "${packages[@]}"

mkdir -p "${MNT}/root/.config/fastfetch" "${home}/.config/fastfetch"

# zsh for the account only: root's shell on a broken boot works without zsh and
# its plugins.
for file in aliases bashrc; do
    render "${data}/${file}" | tee "${MNT}/root/.${file}" "${home}/.${file}" >/dev/null
done
# A login shell reads .bash_profile only, which sources .bashrc. Arch leaves
# root without one.
cp "${MNT}/etc/skel/.bash_profile" "${MNT}/root/.bash_profile"
render "${data}/zshrc" >"${home}/.zshrc"
render "${data}/fastfetch.jsonc" | tee "${MNT}/root/.config/fastfetch/config.jsonc" "${home}/.config/fastfetch/config.jsonc" >/dev/null
arch-chroot "$MNT" chsh -s /usr/bin/zsh "$ARCH_OS_USERNAME"

# Fetched, so the prompt improves without a release. A preset otherwise.
mkdir -p "${MNT}/root/.config"
if ! fetch_url --connect-timeout 5 --max-time 30 \
    https://raw.githubusercontent.com/murkl/starship-theme-arch-os/refs/heads/main/starship.toml \
    >"${home}/.config/starship.toml" || [ ! -s "${home}/.config/starship.toml" ]; then
    echo "fetching the Arch OS prompt theme failed, using a starship preset"
    arch-chroot "$MNT" /usr/bin/starship preset pure-preset -o "/home/${ARCH_OS_USERNAME}/.config/starship.toml"
fi
cp "${home}/.config/starship.toml" "${MNT}/root/.config/starship.toml"

own_home

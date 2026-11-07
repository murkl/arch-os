home="$(user_home)"
data="$(where)"

packages=(git starship eza bat zoxide fd fzf fastfetch mc btop bash-completion
    zsh zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search)

# The prompt's glyphs for a terminal in a window. The console has none,
# see data/bashrc.
[ "$ARCH_OS_DESKTOP" != "none" ] && packages+=(ttf-firacode-nerd)
chroot_pacman_install "${packages[@]}"

run mkdir -p "${MNT}/root/.config/fastfetch" "${home}/.config/fastfetch"

# zsh for the account only: root's shell on a broken boot works without zsh and
# its plugins.
for file in aliases bashrc; do
    render "${data}/${file}" | write_file "${MNT}/root/.${file}" "${home}/.${file}"
done
# A login shell reads .bash_profile only, which sources .bashrc. Arch leaves
# root without one.
run cp "${MNT}/etc/skel/.bash_profile" "${MNT}/root/.bash_profile"
render "${data}/zshrc" | write_file "${home}/.zshrc"
render "${data}/fastfetch.jsonc" | write_file "${MNT}/root/.config/fastfetch/config.jsonc" "${home}/.config/fastfetch/config.jsonc"
run arch-chroot "$MNT" chsh -s /usr/bin/zsh "$ARCH_OS_USERNAME"

# Fetched, so the prompt improves without a release, and the script keeps what
# was fetched. A preset otherwise.
run mkdir -p "${MNT}/root/.config"
theme=https://raw.githubusercontent.com/murkl/starship-theme-arch-os/refs/heads/main/starship.toml
if prompt="$(fetch_url --connect-timeout 5 --max-time 30 "$theme")" && [ -n "$prompt" ]; then
    printf '%s\n' "$prompt" | write_file "${home}/.config/starship.toml"
else
    echo "fetching the Arch OS prompt theme failed, using a starship preset"
    run arch-chroot "$MNT" /usr/bin/starship preset pure-preset -o "/home/${ARCH_OS_USERNAME}/.config/starship.toml"
fi
run cp "${home}/.config/starship.toml" "${MNT}/root/.config/starship.toml"

own_home

# A terminal that is pleasant on the first login rather than after an evening of
# configuration.
#
# Everything it writes is a file beside this one, copied into place.

simulating && return 0

home="${MNT}/home/${ARCH_OS_USERNAME}"
data="$(where)"

packages=(git starship eza bat zoxide fd fzf fastfetch mc btop nano man-db
    bash-completion nano-syntax-highlighting ttf-firacode-nerd ttf-nerd-fonts-symbols)
chroot_pacman_install "${packages[@]}"

mkdir -p "${MNT}/root/.config/fastfetch" "${home}/.config/fastfetch"

# ─── Aliases ─────────────────────────────────────────────────────────────────
# For both root and the user, because the shell is the same shell and muscle
# memory does not check who is logged in.
#
# {{PKG}} and {{SUDO}} in the file are the only part of it the answers decide:
# an AUR helper handles the AUR and the official repositories alike and asks for
# the password itself, so it needs no sudo — pacman does.
pkg="pacman"
sudo_prefix="sudo "
if [ "$ARCH_OS_AUR_HELPER" != "none" ]; then
    pkg="$ARCH_OS_AUR_HELPER"
    sudo_prefix=""
fi

sed -e "s|{{PKG}}|${pkg}|g" -e "s|{{SUDO}}|${sudo_prefix}|g" "${data}/aliases" |
    tee "${MNT}/root/.aliases" "${home}/.aliases" >/dev/null

# ─── Shell configuration ─────────────────────────────────────────────────────
tee "${MNT}/root/.bashrc" "${home}/.bashrc" <"${data}/bashrc" >/dev/null
tee "${MNT}/root/.config/fastfetch/config.jsonc" "${home}/.config/fastfetch/config.jsonc" <"${data}/fastfetch.jsonc" >/dev/null

if [ "$ARCH_OS_SHELL_ENHANCEMENT_FISH_ENABLED" = "true" ]; then
    chroot_pacman_install fish
    mkdir -p "${MNT}/root/.config/fish" "${home}/.config/fish"
    tee "${MNT}/root/.config/fish/config.fish" "${home}/.config/fish/config.fish" <"${data}/config.fish" >/dev/null
fi

# ─── Prompt ──────────────────────────────────────────────────────────────────
# Fetched rather than shipped, so the theme can be improved without a new
# release of this installer. A machine that cannot reach it gets a good one from
# starship itself instead — a missing prompt theme is not worth failing an
# installation over.
mkdir -p "${MNT}/root/.config"
if ! curl -Lf --connect-timeout 5 --max-time 30 \
    https://raw.githubusercontent.com/murkl/starship-theme-arch-os/refs/heads/main/starship.toml \
    >"${home}/.config/starship.toml" || [ ! -s "${home}/.config/starship.toml" ]; then
    echo "the Arch OS prompt theme could not be fetched, falling back to a built-in one"
    arch-chroot "$MNT" /usr/bin/starship preset pure-preset -o "/home/${ARCH_OS_USERNAME}/.config/starship.toml"
fi
cp "${home}/.config/starship.toml" "${MNT}/root/.config/starship.toml"

# ─── Editor ──────────────────────────────────────────────────────────────────
{
    echo 'EDITOR=nano'
    echo 'VISUAL=nano'
} >"${MNT}/etc/environment"

# In each home rather than in /etc/nanorc: that file belongs to the nano package,
# so editing it leaves a .pacnew to merge by hand on every update of it.
mkdir -p "${MNT}/root/.config/nano" "${home}/.config/nano"
tee "${MNT}/root/.config/nano/nanorc" "${home}/.config/nano/nanorc" <"${data}/nanorc" >/dev/null

# ─── What only the first login can do ────────────────────────────────────────
on_first_login <<'FIRST'
# The terminal font, which has to match the one the prompt draws with.
gsettings set org.gnome.desktop.interface monospace-font-name 'FiraCode Nerd Font 11'
FIRST

if [ "$ARCH_OS_SHELL_ENHANCEMENT_FISH_ENABLED" = "true" ]; then
    on_first_login <<'FIRST'
fish -c 'fish_config theme choose Nord && echo y | fish_config theme save'
FIRST
fi

arch-chroot "$MNT" chown -R "${ARCH_OS_USERNAME}:${ARCH_OS_USERNAME}" "/home/${ARCH_OS_USERNAME}"

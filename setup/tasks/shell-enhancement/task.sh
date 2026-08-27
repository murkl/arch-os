# A terminal that is pleasant on the first login rather than after an evening of
# configuration.
#
# Everything static is a file under data/shell and is copied. Only the aliases
# are written here, because which package manager they wrap depends on an answer.

simulating && return 0

home="${MNT}/home/${ARCH_OS_USERNAME}"
data="$(where)"

packages=(git starship eza bat zoxide fd fzf fastfetch mc btop nano man-db
    bash-completion nano-syntax-highlighting ttf-firacode-nerd ttf-nerd-fonts-symbols)
chroot_pacman_install "${packages[@]}"

mkdir -p "${MNT}/root/.config/fastfetch" "${home}/.config/fastfetch"

# ─── Aliases ─────────────────────────────────────────────────────────────────
# Written for both root and the user, because the shell is the same shell and
# muscle memory does not check who is logged in.
pkg="pacman"
sudo_prefix="sudo "
if [ "$ARCH_OS_AUR_HELPER" != "none" ]; then
    # An AUR helper handles the AUR and the official repositories alike, and
    # asks for the password itself.
    pkg="$ARCH_OS_AUR_HELPER"
    sudo_prefix=""
fi

{
    cat <<'ALIASES'
# Listing
alias ls="ls -h --color=always --group-directories-first"
command -v eza &>/dev/null && alias ls="eza --icons --color=always --group-directories-first"
alias ll="ls -l"
alias la="ls -la"
alias lt="ls -Tal"

# Colour
alias diff="diff --color=auto"
alias grep="grep --color=auto"
alias ip="ip -color=auto"

# Everyday
alias logs="systemctl --failed; echo; journalctl -p 3 -b"
alias q="exit"
alias c="clear"
command -v fastfetch &>/dev/null && alias fetch="fastfetch"
command -v meld &>/dev/null && alias pacnew="sudo DIFFPROG=meld pacdiff"
command -v xdg-open &>/dev/null && alias open="xdg-open"
alias myip="curl ipv4.icanhazip.com"
alias ..="cd .."
alias ...="cd ../.."
ALIASES
    echo
    echo '# Packages'
    echo "alias paci='${sudo_prefix}${pkg} -S'    # install"
    echo "alias pacu='${sudo_prefix}${pkg} -Syu'  # update everything"
    echo "alias pacr='${pkg} -Rns'  # remove"
    echo "alias pacs='${pkg} -Ss'   # search the repositories"
    echo "alias pacls='${pkg} -Qs'  # search what is installed"
    echo "alias pacl='${pkg} -Qe'   # list what was asked for"
    echo "alias pacla='${pkg} -Qm'  # list what came from the AUR"
    echo "alias pacli='${pkg} -Qi'  # show a package"
    echo "alias pacrc='${pkg} -Scc' # clear the download cache"
} | tee "${MNT}/root/.aliases" "${home}/.aliases" >/dev/null

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

sed -i "s/^# set linenumbers/set linenumbers/" "${MNT}/etc/nanorc"
sed -i "s/^# set minibar/set minibar/" "${MNT}/etc/nanorc"
sed -i 's;^# include /usr/share/nano/\*\.nanorc;include /usr/share/nano/*.nanorc\ninclude /usr/share/nano/extra/*.nanorc\ninclude /usr/share/nano-syntax-highlighting/*.nanorc;g' "${MNT}/etc/nanorc"

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

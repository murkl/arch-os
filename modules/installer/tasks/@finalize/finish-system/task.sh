# The last two things done to the new system before it is handed over: what
# earlier tasks left for the first login, and the packages nothing needs any
# more.

simulating && return 0

# Packages pulled in as dependencies of something that has since gone.
# shellcheck disable=SC2016  # pacman inside the chroot expands this, not us
arch-chroot "$MNT" bash -c 'pacman -Qtdq >/dev/null 2>&1 && pacman -Rns --noconfirm $(pacman -Qtdq) || true'

# ----------------------------------------------------------------------------

# Settings that live in the user's own database, which needs a session that does
# not exist yet. Earlier tasks appended their lines to one file; it becomes a
# script that runs once at the first login and removes itself.
[ -s "$FIRST_LOGIN" ] || return 0

home="${MNT}/home/${ARCH_OS_USERNAME}"
mkdir -p "${home}/.arch-os" "${home}/.config/autostart"
{
    echo '#!/usr/bin/env bash'
    echo '# Written by the Arch OS Installer. Runs once, at the first login.'
    cat "$FIRST_LOGIN"
    echo
    echo '# Nothing here is worth doing twice.'
    echo "rm -f \"\${HOME}/.config/autostart/arch-os-first-login.desktop\""
    echo "echo \"\$(date '+%Y-%m-%d %H:%M:%S') | first login done\""
} >"${home}/.arch-os/first-login.sh"
rm -f "$FIRST_LOGIN"
arch-chroot "$MNT" chmod +x "/home/${ARCH_OS_USERNAME}/.arch-os/first-login.sh"

{
    echo '[Desktop Entry]'
    echo 'Type=Application'
    echo 'Name=Arch OS Setup'
    echo 'Icon=preferences-system'
    echo "Exec=bash -c '\${HOME}/.arch-os/first-login.sh > \${HOME}/.arch-os/first-login.log 2>&1'"
} >"${home}/.config/autostart/arch-os-first-login.desktop"

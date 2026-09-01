# A handful of settings can only be applied by the user's own session, because
# they live in that session's settings database and there is no session yet.
# Earlier tasks appended their lines to one file; it becomes a script that
# runs once, at the first login, and removes itself.

simulating && return 0

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

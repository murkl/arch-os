# Settings that live in the user's own database, which needs a session. Earlier
# tasks appended their lines through on_first_login; here they become a script
# that runs once at the first login and removes its own autostart entry.
# Where the pieces land follows the XDG base directories, clear of ~/.arch-os,
# which belongs to the manager. https://specifications.freedesktop.org/basedir-spec/latest/

# A console system has no session to wait for.
[ -s "$FIRST_LOGIN" ] || return 0

script=.local/share/arch-os/first-login.sh
log=.local/state/arch-os/first-login.log
entry=.config/autostart/arch-os-first-login.desktop

mkdir -p "${HOME_DIR}/${script%/*}" "${HOME_DIR}/${log%/*}" "${HOME_DIR}/${entry%/*}"
{
    echo '#!/usr/bin/env bash'
    echo '# Written by the Arch OS Installer. Runs once, at the first login.'
    cat "$FIRST_LOGIN"
    echo
    echo "rm -f \"\${HOME}/${entry}\""
    echo "echo \"\$(date '+%Y-%m-%d %H:%M:%S') | first login done\""
} >"${HOME_DIR}/${script}"
rm -f "$FIRST_LOGIN"
chmod +x "${HOME_DIR}/${script}"

render "$(where)/arch-os-first-login.desktop" SCRIPT="$script" LOG="$log" >"${HOME_DIR}/${entry}"

# Written as root into somebody else's home.
own_home

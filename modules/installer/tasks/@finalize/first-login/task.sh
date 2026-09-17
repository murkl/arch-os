# Settings that live in the user's own database, which needs a session that does
# not exist yet. Earlier tasks appended their lines to one file; here it becomes
# a script that runs once at the first login and removes itself.
#
# See on_first_login in module.sh for the other end, and FIRST_LOGIN beside it
# for where the three pieces of this land.

simulating && return 0

# Nothing to do is an ordinary outcome: a console system with no desktop has no
# session to wait for and nothing to put in one.
[ -s "$FIRST_LOGIN" ] || return 0

mkdir -p "$(dirname "$FIRST_LOGIN_SCRIPT")" "${HOME_DIR}/${FIRST_LOGIN_LOG%/*}" "$(dirname "$FIRST_LOGIN_ENTRY")"
{
    echo '#!/usr/bin/env bash'
    echo '# Written by the Arch OS Installer. Runs once, at the first login.'
    cat "$FIRST_LOGIN"
    echo
    echo '# Nothing here is worth doing twice: the entry that started this is what'
    echo '# makes it run, so dropping it is what makes it a first login.'
    echo "rm -f \"\${HOME}/${FIRST_LOGIN_ENTRY#"${HOME_DIR}"/}\""
    echo "echo \"\$(date '+%Y-%m-%d %H:%M:%S') | first login done\""
} >"$FIRST_LOGIN_SCRIPT"
rm -f "$FIRST_LOGIN"
chmod +x "$FIRST_LOGIN_SCRIPT"

# The desktop entry every desktop reads at login, and the one thing here a
# person might want to look at afterwards: what the script made of it.
{
    echo '[Desktop Entry]'
    echo 'Type=Application'
    echo 'Name=Arch OS Setup'
    echo 'Icon=preferences-system'
    echo "Exec=bash -c '\"\${HOME}/${FIRST_LOGIN_SCRIPT#"${HOME_DIR}"/}\" >\"\${HOME}/${FIRST_LOGIN_LOG}\" 2>&1'"
} >"$FIRST_LOGIN_ENTRY"

# Everything above was written as root into somebody else's home, and a first
# login that cannot write its own log is one that reports nothing.
own_home

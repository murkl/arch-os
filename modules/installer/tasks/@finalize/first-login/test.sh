# An autostart entry pointing at a script that is not there is a first login
# that quietly does nothing and says so nowhere, so the two are checked
# together: either both or neither. Nothing left to do is an ordinary outcome
# rather than a failure, which is what the first line allows for.
debugging && return 0

[ -f "$FIRST_LOGIN_ENTRY" ] || return 0

[ -x "$FIRST_LOGIN_SCRIPT" ]
[ -d "${HOME_DIR}/${FIRST_LOGIN_LOG%/*}" ]

# And it belongs to the account that will run it: all of this was written as
# root into somebody else's home, and a login that cannot write its own log
# reports nothing. By number, because the account exists in the new system and
# not out here.
uid="$(arch-chroot "$MNT" id -u "$ARCH_OS_USERNAME")"
[ "$(stat -c %u "$FIRST_LOGIN_SCRIPT")" = "$uid" ]

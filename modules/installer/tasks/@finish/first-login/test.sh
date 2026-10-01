# The entry and the script it starts, together or not at all: an entry pointing
# at nothing does nothing and says so nowhere.
home="$(user_home)"
entry="${home}/.config/autostart/arch-os-first-login.desktop"
[ -f "$entry" ] || return 0

mapfile -t paths < <(grep -o '[$]{HOME}/[^"]*' "$entry" | sed 's|^[$]{HOME}/||')
script="${home}/${paths[0]}"
log="${home}/${paths[1]}"
[ -x "$script" ]
[ -d "${log%/*}" ]

# Owned by the account that runs it, by number: it exists in there, not here.
uid="$(arch-chroot "$MNT" id -u "$ARCH_OS_USERNAME")"
[ "$(stat -c %u "$script")" = "$uid" ]

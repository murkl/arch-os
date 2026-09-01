# The answers, put where another machine can pick them up.
#
# An installation is two dozen answers, and the next machine set up the same way
# is otherwise those answers given again by hand. So the finished configuration
# can be put where a phone reaches it, and a starting point can take its answers
# from there — see import.sh beside this file for the other end.
#
# Only ever the answer file: a user name, a host name, a disk, a language. The
# password is not in it — the runtime never writes a secret down.
#
# Nothing here runs unasked: the task offers itself first and opens on no. It is
# the only thing in this tree that sends anything anywhere.
#
# Nothing here may fail the installation either: the system on the disk is
# finished by the time this is offered, and an unreachable pastebin says nothing
# about it.

# paste.rs takes a file over an ordinary POST, answers with the address it now
# lives at, and serves it back as plain text. No account, no key.
service="https://paste.rs"

# An answer, appended to the file the runtime keeps them in — one KEY='value' to
# a line, which the runtime reads back. Any earlier line for the same name is
# dropped, so a file somebody opens does not say a thing twice.
#
# Written whole and moved into place: a script interrupted mid-write must not
# leave half a file where the answers were.
answer() {
    local tmp="${INSTALLER_CONF}.answer"
    grep -v "^${1}=" "$INSTALLER_CONF" >"$tmp" 2>/dev/null || : >>"$tmp"
    printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")" >>"$tmp"
    mv -f "$tmp" "$INSTALLER_CONF"
}

# Simulated, this still answers with an address: the page at the end of a run is
# the one most worth looking at while this tree is being worked on.
simulating && {
    answer ARCH_OS_CONFIG_URL "${service}/demo"
    return 0
}

# Everything this installation was told, without the lines about the sharing
# itself: a configuration naming where an earlier copy went would send whoever
# opened it somewhere else again.
if ! url="$(grep -v '^ARCH_OS_CONFIG_' "$INSTALLER_CONF" |
    curl -sf --connect-timeout 10 --max-time 30 --data-binary @- "${service}/")"; then
    echo "the configuration could not be shared" >&2
    return 0
fi

url="$(printf '%s' "$url" | tr -d '[:space:]')"
[ -n "$url" ] || return 0

# Kept as an answer of its own, which is what puts it on the page the run stops
# on next.
answer ARCH_OS_CONFIG_URL "$url"

# And into the copy already in the new system — see the copy-config task: the one
# record of it that survives the machine being restarted.
target="${MNT}/home/${ARCH_OS_USERNAME}/installer.conf"
[ -f "$target" ] && printf "ARCH_OS_CONFIG_URL='%s'\n" "$url" >>"$target"

echo "shared at ${url}"

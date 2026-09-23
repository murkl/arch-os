# The answers put where another machine can pick them up - see import.sh beside
# this file for the other end. Only ever the answer file, which holds no
# password, and only ever after the offer in task.yaml was accepted.
#
# Nothing here may fail the installation: the system on the disk is finished by
# the time this is offered, and an unreachable pastebin says nothing about it.

# paste.rs takes a file over an ordinary POST, answers with the address it now
# lives at, and serves it back as plain text. No account, no key.
service="https://paste.rs"

# An answer, appended to the file Oak keeps them in and reads back. Any earlier
# line for the same name is dropped, and the file is written whole and moved
# into place.
answer() {
    local tmp="${MODULE_CONF}.answer"
    grep -v "^${1}=" "$MODULE_CONF" >"$tmp" 2>/dev/null || : >>"$tmp"
    printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")" >>"$tmp"
    mv -f "$tmp" "$MODULE_CONF"
}

# Simulated, this still answers with an address - it is why task.yaml says it
# simulates itself: the page at the end of a run is the one most worth looking
# at while this module is being worked on.
debugging && {
    answer ARCH_OS_CONFIG_URL "${service}/demo"
    return 0
}

# Without the lines about the sharing itself: a configuration naming where an
# earlier copy went would send whoever opened it somewhere else again.
if ! url="$(grep -v '^ARCH_OS_CONFIG_' "$MODULE_CONF" |
    curl -sf --connect-timeout 10 --max-time 30 --data-binary @- "${service}/")"; then
    echo "the configuration could not be shared" >&2
    return 0
fi

url="$(printf '%s' "$url" | tr -d '[:space:]')"
[ -n "$url" ] || return 0

# An answer of its own, which is what puts it on the page the run stops on next.
answer ARCH_OS_CONFIG_URL "$url"

# And into the copy already in the new system, which is the one record of it
# that survives the machine being restarted.
target="${MNT}/home/${ARCH_OS_USERNAME}/installer.conf"
[ -f "$target" ] && printf "ARCH_OS_CONFIG_URL='%s'\n" "$url" >>"$target"

echo "shared at ${url}"

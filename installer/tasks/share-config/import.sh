# A configuration somebody shared, taken as the answers to this installation.
# The other end of task.sh beside it.
#
# Run by the starting point that asks for a code, the moment the code is
# given, and the row is not passed until it succeeds. What the runtime owns
# is left alone: the interface language and the mode are settings of the
# program in front of you, not of somebody else's machine.
#
# This one is allowed to fail, and says why: it runs while somebody is
# looking at the box they typed the code into.

# The address, from whatever somebody has in front of them: the whole link,
# or just the code at the end of it.
ref="$(printf '%s' "$ARCH_OS_CONFIG_SOURCE" | tr -d '[:space:]')"
case "$ref" in
http://* | https://*) url="$ref" ;;
*) url="https://paste.rs/${ref##*/}" ;;
esac

if ! body="$(curl -Lsf --connect-timeout 10 --max-time 30 "$url")"; then
    echo "Nothing could be read at ${url}" >&2
    exit 1
fi

body="$(printf '%s\n' "$body" | grep '^ARCH_OS_[A-Z0-9_]*=' | grep -v '^ARCH_OS_CONFIG_' || true)"
if [ -z "$body" ]; then
    echo "What is kept at ${url} is not an Arch OS configuration" >&2
    exit 1
fi

# Appended to the answer file, which the runtime reads back. That file is how
# a script answers questions, and there is no second way in.
printf '%s\n' "$body" >>"$INSTALLER_CONF"

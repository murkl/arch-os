# A configuration somebody shared, taken as the answers to this installation -
# the other end of task.sh beside it. Run by the starting point that asks for a
# code, and the row is not passed until it succeeds.
#
# This one is allowed to fail and says why: it runs while somebody is looking at
# the box they typed the code into.

# The address, from whatever somebody has in front of them: the whole link, or
# just the code at the end of it. Only the code is kept and always asked of
# paste.rs over https, which is the one place task.sh ever shares to.
ref="$(printf '%s' "$ARCH_OS_CONFIG_SOURCE" | tr -d '[:space:]')"
url="https://paste.rs/${ref##*/}"

if ! body="$(fetch_url -s --connect-timeout 10 --max-time 30 "$url")"; then
    echo "Nothing could be read at ${url}" >&2
    exit 1
fi

# Everything but the sharing itself and the disk: a disk is a path on the
# machine the answers were given on, and here another disk - or this very
# medium - may sit at it. The disk is asked again, which is the one question a
# starting point leaves to the person at the machine anyway.
body="$(printf '%s\n' "$body" | grep '^ARCH_OS_[A-Z0-9_]*=' |
    grep -vE '^ARCH_OS_(CONFIG_[A-Z_]*|DISK)=' || true)"
if [ -z "$body" ]; then
    echo "What is kept at ${url} is not an Arch OS configuration" >&2
    exit 1
fi

# Appended to the answer file, which Oak reads back. That file is how a script
# answers questions, and there is no second way in.
printf '%s\n' "$body" >>"$MODULE_CONF"

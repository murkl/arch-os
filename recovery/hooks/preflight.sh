# Can this machine run a recovery at all?
#
# Everything here is read-only, and every check is a hard stop. Runs before
# the first question, because none of it can be fixed from inside this
# program.
#
# It asks nothing of the machine beyond being the live image: not its
# firmware, which isn't what is being repaired, and not a network, because a
# recovery downloads nothing - which is the whole point on a machine whose
# network may be exactly what stopped working.
#
# What goes to stderr is what the user reads, so each message says what is
# wrong and what to do about it, in that order, and nothing else.

# DEBUG=true simulates the recovery instead of running it, on a machine where
# neither of the checks below would pass.
[ "$DEBUG" = "true" ] && return 0

if [ "$(id -u)" -ne 0 ]; then
    echo "This has to run as root. Log in as root and start it again." >&2
    exit 1
fi

if [ "$(cat /proc/sys/kernel/hostname)" != "archiso" ]; then
    echo "This only runs from the Arch Linux live image. Boot that image and start it from there." >&2
    exit 1
fi

echo "preflight ok: root, live image"

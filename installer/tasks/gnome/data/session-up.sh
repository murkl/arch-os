#!/usr/bin/env bash
# Waits up to $1 seconds for a graphical session on seat0, the greeter's or an
# automatic login's. Until then the boot does not count as good.
# https://systemd.io/AUTOMATIC_BOOT_ASSESSMENT/
set -u

deadline=$((SECONDS + $1))
while [ "$SECONDS" -lt "$deadline" ]; do
    session="$(loginctl show-seat seat0 -p ActiveSession --value 2>/dev/null)"
    user=""
    [ -z "$session" ] || user="$(loginctl show-session "$session" -p Name --value 2>/dev/null)"
    if [ -n "$user" ] && systemctl --user -M "${user}@" is-active --quiet graphical-session.target 2>/dev/null; then
        echo "the session of ${user} is up"
        exit 0
    fi
    sleep 2
done

echo "no session on seat0 was up within $1 s" >&2
loginctl list-sessions --no-pager >&2
exit 1

#!/usr/bin/env bash
# data/arch-os-recovery, which shellcheck cannot read, started headless as the app
# grid starts it: it opens without an error and waits for an answer.
#
#   check.sh
set -euo pipefail

cd "$(dirname "$0")"

work="$(mktemp -d)"
broadway=""
cleanup() {
    if [ -n "$broadway" ]; then kill "$broadway" 2>/dev/null || true; fi
    rm -rf "$work"
}
trap cleanup EXIT

# The socket lies in a private folder. The page binds port 8080 plus the display,
# which differs per run, so checks run side by side.
display=$(($$ % 900 + 100))
socket="${work}/broadway$((display + 1)).socket"
export XDG_RUNTIME_DIR="$work" GDK_BACKEND=broadway BROADWAY_DISPLAY=":${display}"
gtk4-broadwayd --address 127.0.0.1 "$BROADWAY_DISPLAY" >"${work}/broadway" 2>&1 &
broadway=$!
for _ in {1..50}; do
    if [ -S "$socket" ]; then break; fi
    sleep 0.1
done
# The page binds after the socket, so a taken port shows a moment later.
sleep 0.2
if [ ! -S "$socket" ] || ! kill -0 "$broadway" 2>/dev/null; then
    echo "FAIL  dialog: gtk4-broadwayd not running"
    cat "${work}/broadway"
    exit 1
fi

status=0
timeout 5 gjs -m data/arch-os-recovery 2>"${work}/log" || status=$?
if [ "$status" -eq 124 ] && ! grep -qE 'JS (ERROR|WARNING)|CRITICAL' "${work}/log"; then
    echo "ok    dialog"
else
    echo "FAIL  dialog: exit ${status}"
    cat "${work}/log"
    exit 1
fi

#!/usr/bin/env bash
# Checks boot-tries.sh against the entries as the Installer writes them, as the
# loader and systemd-bless-boot leave them, and beside a default in loader.conf.
#
#   check.sh
set -euo pipefail

cd "$(dirname "$0")"

status=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Runs boot-tries.sh on an EFI partition with the entries named and compares
# exit status and entries. The entry `default` goes into loader.conf.
case_of() {
    local what="$1" entries="$2" want_status="$3" want="$4" esp got_status=0 got
    esp="${work}/${what// /-}"
    mkdir -p "${esp}/loader/entries"
    for entry in $entries; do
        if [ "$entry" = default ]; then
            echo 'default arch-linux-zen.efi' >"${esp}/loader/loader.conf"
        else
            echo "title ${entry}" >"${esp}/loader/entries/${entry}"
        fi
    done
    bash boot-tries.sh "$esp" 3 >/dev/null 2>&1 || got_status=$?
    got="$(find "${esp}/loader/entries" -type f -printf '%f\n' | sort | paste -sd' ')"
    if [ "$got_status" != "$want_status" ] || [ "$got" != "$want" ]; then
        printf '%s\n  got:  %s %s\n  want: %s %s\n' "$what" "$got_status" "$got" "$want_status" "$want" >&2
        status=1
    fi
}

case_of "as installed" "main+3.conf main-fallback+3.conf" 0 "main+3.conf main-fallback+3.conf"
case_of "one try taken" "main+2-1.conf main-fallback+3.conf" 0 "main+3.conf main-fallback+3.conf"
case_of "blessed" "main.conf main-fallback+3.conf" 0 "main+3.conf main-fallback+3.conf"
case_of "every try used" "main+0-3.conf main-fallback+0-3.conf" 0 "main+3.conf main-fallback+3.conf"
case_of "no fallback" "main+1-2.conf" 0 "main+3.conf"
case_of "an entry twice" "main.conf main+1-2.conf" 1 "main+1-2.conf main.conf"
case_of "a default named" "default main.conf" 0 "main.conf"
case_of "no entries" "" 0 ""
case_of "another entry" "main+3.conf windows.conf" 0 "main+3.conf windows.conf"

[ "$status" -eq 0 ] && echo "boot-tries.sh passes every case"
exit "$status"

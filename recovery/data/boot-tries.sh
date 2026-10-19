#!/usr/bin/env bash
# Written by Arch OS: the system's boot entries on the EFI partition $1 given
# $2 tries again, after a start that worked and whenever the Recovery starts.
# The loader takes one each time it starts an entry, and one with none left
# goes behind the others: the fallback, then the Recovery.
# https://systemd.io/AUTOMATIC_BOOT_ASSESSMENT/
set -eu

entries="$1/loader/entries"

# A default in loader.conf starts however often it failed: nothing here would
# change that.
if grep -qs '^default' "$1/loader/loader.conf"; then
    exit 0
fi

for name in main main-fallback; do
    found=()
    for file in "${entries}/${name}.conf" "${entries}/${name}+"*.conf; do
        [ ! -e "$file" ] || found+=("$file")
    done
    case "${#found[@]}" in
    0) continue ;;
    1) ;;
    *)
        echo "${entries} holds ${name} more than once: ${found[*]}" >&2
        exit 1
        ;;
    esac
    want="${entries}/${name}+$2.conf"
    if [ "${found[0]}" != "$want" ]; then
        mv -f "${found[0]}" "$want"
        echo "${found[0]##*/} is ${want##*/} again"
    fi
done

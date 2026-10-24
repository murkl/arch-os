#!/usr/bin/env bash
# Written by Arch OS. Gives the boot entries on the EFI partition $1 $2 tries
# again, after a good start and at every Recovery start. An entry out of tries
# sorts last, so the fallback starts, then the Recovery.
# https://systemd.io/AUTOMATIC_BOOT_ASSESSMENT/
set -eu

entries="$1/loader/entries"

# A default in loader.conf starts regardless of its tries.
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
        echo "renamed ${found[0]##*/} to ${want##*/}"
    fi
done

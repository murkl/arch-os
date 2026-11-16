#!/usr/bin/env bash
# Keeps one snapshot of the system as it last started well. It has no cleanup
# algorithm, so the limit for the snapshots around package transactions leaves
# it alone.
set -euo pipefail

MARK="arch-os=boot"

# The new one first: a failed create leaves the one before.
new="$(snapper -c root create --print-number --description "last good boot" --userdata "$MARK")"

list="$(snapper -c root --csvout --no-headers list --columns number,userdata)"
old=()
while IFS=, read -r number userdata; do
    if [ "$userdata" = "$MARK" ] && [ "$number" != "$new" ]; then
        old+=("$number")
    fi
done <<<"$list"

[ "${#old[@]}" -eq 0 ] || snapper -c root delete "${old[@]}"
echo "snapshot ${new} holds this start"

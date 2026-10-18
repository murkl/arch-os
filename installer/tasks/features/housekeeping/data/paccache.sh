#!/usr/bin/env bash
# Written by the Arch OS Installer. The package cache trimmed as paccache trims
# it, except for every kernel package a snapshot has installed: the Recovery
# rebuilds a rolled back snapshot's boot files from that package, whatever its
# age. Run as root by paccache.service and by pacrc, the options go to paccache.
#
#   paccache.sh <snapshots> [paccache options]
set -euo pipefail
shopt -s nullglob

snapshots="$1"
shift

# Each kernel a snapshot has installed, as name-version-release, and its name.
# A kernel package is one that holds a vmlinuz. All of Arch's are named linux*.
# One that cannot be read stops the trim, which would otherwise take it.
keep=()
names=()
for dir in "${snapshots}"/*/snapshot/var/lib/pacman/local/linux*/; do
    status=0
    grep -q '^usr/lib/modules/[^/]*/vmlinuz$' "${dir}files" || status=$?
    case "$status" in
    0) ;;
    1) continue ;;
    *) exit 1 ;;
    esac
    keep+=("$(basename "$dir")")
    names+=("$(sed -n '/^%NAME%$/{n;p;q}' "${dir}desc")")
done

if [ "${#keep[@]}" -eq 0 ]; then
    exec paccache -r "$@"
fi
mapfile -t names < <(printf '%s\n' "${names[@]}" | sort -u)

# Everything else as paccache.service trims it.
paccache -r "$@" --ignore "$(
    IFS=,
    echo "${names[*]}"
)"

# The kernels: what paccache would take, unless a snapshot has it installed.
mapfile -t caches < <(pacman-conf CacheDir)
candidates="$(paccache -d -v --nocolor "$@" "${names[@]}")"
while read -r file; do
    for key in "${keep[@]}"; do
        if [[ $file == "$key"-* ]]; then continue 2; fi
    done
    for cache in "${caches[@]}"; do
        if [ -f "${cache%/}/${file}" ]; then
            rm -f -- "${cache%/}/${file}"
            echo "removed ${cache%/}/${file}"
        fi
    done
done < <(sed -n '/^==> Candidate packages:$/,/^$/{/^==>/d;/^$/d;p}' <<<"$candidates")

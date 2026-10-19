#!/usr/bin/env bash
# data/bashrc and data/zshrc on a text console: every value of environment.d,
# a quoted one too, arrives as it is written there.
#
#   check.sh
set -euo pipefail

cd "$(dirname "$0")"

status=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "${work}/environment.d" "${work}/home"
: >"${work}/home/.aliases"
want="sh -c 'col -bx | bat -l man -p'"
printf 'CHECK_VALUE="%s"\n' "$want" >"${work}/environment.d/50-check.conf"

# A login on the text console: no display, an empty environment, the first shell level.
console=(env -i "HOME=${work}/home" "PATH=${PATH}" "XDG_CONFIG_HOME=${work}" TERM=linux)
declare -A got
# shellcheck disable=SC2016 # the shell started here expands them
got[bash]="$("${console[@]}" bash --norc -i -c 'source "$1"; printf "%s" "$CHECK_VALUE"' bash data/bashrc 2>/dev/null)"
# shellcheck disable=SC2016
got[zsh]="$("${console[@]}" zsh -f -i -c 'source "$1"; print -rn -- "$CHECK_VALUE"' zsh data/zshrc 2>/dev/null)"

for shell in bash zsh; do
    if [ "${got[$shell]}" = "$want" ]; then
        echo "ok    ${shell}"
    else
        echo "FAIL  ${shell}: got '${got[$shell]}', want '${want}'"
        status=1
    fi
done
exit "$status"

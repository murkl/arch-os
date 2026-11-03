#!/usr/bin/env bash
# data/bashrc and data/zshrc: on a console every value of environment.d,
# quoted ones included, arrives as written. A graphical session got them with
# the session, so its shells import nothing, also without Xwayland's DISPLAY.
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

# CHECK_VALUE as shell $1 sees it in a login of session type $2: an empty
# environment, no display, the first shell level.
value() {
    local login=(env -i "HOME=${work}/home" "PATH=${PATH}" "XDG_CONFIG_HOME=${work}" "XDG_SESSION_TYPE=$2" TERM=linux)
    # shellcheck disable=SC2016 # the shell started here expands them
    case "$1" in
    bash) "${login[@]}" bash --norc -i -c 'source "$1"; printf "%s" "$CHECK_VALUE"' bash data/bashrc 2>/dev/null ;;
    zsh) "${login[@]}" zsh -f -i -c 'source "$1"; print -rn -- "$CHECK_VALUE"' zsh data/zshrc 2>/dev/null ;;
    esac
}

for shell in bash zsh; do
    for session in tty wayland; do
        expected=""
        [ "$session" = tty ] && expected="$want"
        got="$(value "$shell" "$session")"
        if [ "$got" = "$expected" ]; then
            echo "ok    ${shell} ${session}"
        else
            echo "FAIL  ${shell} ${session}: got '${got}', want '${expected}'"
            status=1
        fi
    done
done
exit "$status"

#!/usr/bin/env sh
# Arch OS, from one command:
#
#   curl -Ls https://bit.ly/archos | bash
#
# Fetches the latest release, checks it, unpacks it and starts it. Each module
# decides itself whether this machine is one it runs on.
#
# Whatever is passed on the right of the pipe goes to the program, so
# `bash -s -- --debug` is a run that changes nothing. POSIX sh, because this
# runs before anything of the project is on the machine.
set -eu

REPO="murkl/arch-os"

# The program keeps its answers and its log beside itself, so the next run
# finds them here. No sudo: a live image runs this as root already, and
# elsewhere the module asks for root for the one command that needs it.
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${XDG_DOWNLOAD_DIR:-${HOME}/Downloads}}"

info() { printf ':: %s\n' "$1"; }
fail() {
    printf ':: \033[31m%s\033[0m\n' "$1" >&2
    exit 1
}

for command_name in curl tar sha256sum; do
    command -v "$command_name" >/dev/null || fail "Missing dependency: ${command_name}"
done

# https even after a redirect: -L alone would follow a 302 into plain http.
fetch() { curl --proto '=https' --proto-redir '=https' --connect-timeout 10 "$@"; }

# Said here rather than as "cannot execute binary file" at the exec.
[ "$(uname -m)" = "x86_64" ] || fail "Arch OS is x86_64 only, and this machine is $(uname -m)"

# The program asks things, and through a pipe stdin is this script.
[ -r /dev/tty ] || fail "No terminal, run this from an interactive shell"

mkdir -p "$DOWNLOAD_DIR" || fail "Cannot write to ${DOWNLOAD_DIR}"
cd "$DOWNLOAD_DIR"

printf '\n\033[34m// Arch OS\033[0m\n'

# The program and its sha256 out of GitHub's description of the latest release,
# picked by what the name ends in. Read into a variable first, so an
# unreachable GitHub and a release without a program say different things.
release="$(fetch -Lfs "https://api.github.com/repos/${REPO}/releases/latest")" || fail "Cannot reach GitHub"

# One field to a line, however GitHub lays the JSON out, and each asset weighed
# when the next one begins, whatever order its fields come in.
asset="$(printf '%s\n' "$release" | tr ',' '\n' | awk '
    function weigh() {
        if (!found && url ~ /\.tar\.gz$/) { found = 1; print url, digest }
        url = ""; digest = ""
    }
    /"url": *"[^"]*\/releases\/assets\// { weigh() }
    /"digest": *"sha256:/ { digest = $0; sub(/.*sha256:/, "", digest); sub(/".*/, "", digest) }
    /"browser_download_url": *"/ { url = $0; sub(/.*: *"/, "", url); sub(/".*/, "", url) }
    END { weigh() }')"
[ -n "$asset" ] || fail "The latest release holds no program"

url="${asset%% *}"
digest="${asset##* }"
name="${url##*/}"
[ -n "$digest" ] || fail "The latest release publishes no checksum for ${name}"

# Written to a .part and moved into place, so a file that is there arrived
# whole and may be skipped.
if [ -f "$name" ]; then
    info "Present: ${name}"
else
    info "Fetching: ${name}"
    fetch -Lf --progress-bar "$url" -o "${name}.part" || fail "Download failed: ${name}"
    mv "${name}.part" "$name"
fi

# Checked on every run, so a damaged leftover is caught too and thrown away.
if ! echo "${digest}  ${name}" | sha256sum -c - >/dev/null 2>&1; then
    rm -f "$name"
    fail "Checksum mismatch: ${name} was discarded, please run this again"
fi
info "Checksum is correct"

# The folder is named by the archive, which carries the version. awk rather
# than `head -n1`, which closes the pipe on tar.
tar -xzf "$name" || fail "Cannot unpack ${name}"
dir="$(tar -tzf "$name" | awk -F/ 'NR == 1 { print $1 }')"
[ -x "${dir}/oak" ] || fail "No program in ${name}"
info "Unpacked: ${DOWNLOAD_DIR}/${dir}"

# Started in its own folder: it reads the oak.yaml beside it and writes there.
cd "$dir"
exec ./oak "$@" </dev/tty

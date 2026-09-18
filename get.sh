#!/usr/bin/env sh
# Arch OS, from one command:
#
#   curl -Ls https://bit.ly/arch-os | bash
#
# Fetches the latest release, checks it, unpacks it and starts it. What this
# machine is good for is not decided here but by the program itself: each module
# carries the check that says whether this is a machine it can run on.
#
# Whatever is passed on the right of the pipe goes straight to the program, so
# `bash -s -- --debug` is a run that changes nothing. POSIX sh, because this
# runs before anything of the project is on the machine.
set -eu

REPO="murkl/arch-os"

# Where the release is unpacked, and where the next run finds it again. The
# program keeps its answers and its log beside its own binary, so a second run
# picks up where the first left off.
#
# No sudo anywhere in here, and none wanted on the left of the pipe: on a live
# image whoever runs this is root already, and on an ordinary machine the module
# that opens there asks for root itself, for the one command that needs it.
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${XDG_DOWNLOAD_DIR:-${HOME}/Downloads}}"

info() { printf ':: %s\n' "$1"; }
fail() {
    printf ':: \033[31m%s\033[0m\n' "$1" >&2
    exit 1
}

for command_name in curl tar sha256sum; do
    command -v "$command_name" >/dev/null || fail "Missing dependency: ${command_name}"
done

# https even after a redirect: -L on its own would follow a 302 into plain http,
# where the answer is whoever is on the wire - and the answer here is the program
# that goes on to write a disk.
fetch() { curl --proto '=https' --proto-redir '=https' --connect-timeout 10 "$@"; }

# Said here rather than left to the exec at the end, where a machine of another
# shape learns it as "cannot execute binary file".
[ "$(uname -m)" = "x86_64" ] || fail "Arch OS is x86_64 only, and this machine is $(uname -m)"

# The program asks things, and through a pipe stdin is this script rather than
# the person who started it.
[ -r /dev/tty ] || fail "No terminal, run this from an interactive shell"

mkdir -p "$DOWNLOAD_DIR" || fail "Cannot write to ${DOWNLOAD_DIR}"
cd "$DOWNLOAD_DIR"

printf '\n\033[34m// Arch OS\033[0m\n'

# Where the latest release keeps the program and what it has to hash to, out of
# GitHub's own description of it - the release carries no checksum file of its
# own. Picked by what the name ends in rather than by the name itself, so
# renaming a download stays a change to the build and nothing here.
#
# Each asset is weighed when the next one begins, so nothing here leans on the
# order GitHub writes an asset's fields in.
asset="$(fetch -Lfs "https://api.github.com/repos/${REPO}/releases/latest" | awk '
    function weigh() {
        if (!found && url ~ /\.tar\.gz$/) { found = 1; print url, digest }
        url = ""; digest = ""
    }
    /"url": *"[^"]*\/releases\/assets\// { weigh() }
    /"digest": *"sha256:/ { digest = $0; sub(/.*sha256:/, "", digest); sub(/".*/, "", digest) }
    /"browser_download_url": *"/ { url = $0; sub(/.*: *"/, "", url); sub(/".*/, "", url) }
    END { weigh() }')" || fail "Cannot reach GitHub"
[ -n "$asset" ] || fail "The latest release holds no program"

url="${asset%% *}"
digest="${asset##* }"
name="${url##*/}"
[ -n "$digest" ] || fail "The latest release publishes no checksum for ${name}"

# Written to a .part and moved into place afterwards, so a file that is there is
# a file that arrived whole — which is what makes skipping it safe.
if [ -f "$name" ]; then
    info "Present: ${name}"
else
    info "Fetching: ${name}"
    fetch -Lf --progress-bar "$url" -o "${name}.part" || fail "Download failed: ${name}"
    mv "${name}.part" "$name"
fi

# Against what GitHub publishes beside the download, which is the check anybody
# would run by hand off the release page. Read off the file every run, so a
# truncated leftover from last time is caught too; one that fails is thrown away
# rather than kept.
if ! echo "${digest}  ${name}" | sha256sum -c - >/dev/null 2>&1; then
    rm -f "$name"
    fail "Checksum mismatch: ${name} was discarded, please run this again"
fi
info "Checksum is correct"

# Named by the archive rather than by this script: it carries the version, and
# which version that is belongs to the build. awk rather than `head -n1`, which
# closes the pipe on tar and leaves a write error behind.
tar -xzf "$name" || fail "Cannot unpack ${name}"
dir="$(tar -tzf "$name" | awk -F/ 'NR == 1 { print $1 }')"
[ -x "${dir}/oak" ] || fail "No program in ${name}"
info "Unpacked: ${DOWNLOAD_DIR}/${dir}"

# Out of its own folder, because the program reads the oak.yaml beside its
# binary and keeps everything it writes there too.
cd "$dir"
exec ./oak "$@" </dev/tty

#!/usr/bin/env sh
# Arch OS, from one command:
#
#   curl -Ls bit.ly/arch-os | sudo bash
#
# Fetches the latest release, checks it, unpacks it and starts it. That is the
# whole of this script: what this machine is good for is not decided here but by
# the program itself — each of its modules carries the checks that say whether
# this is a machine it can run on, so an Arch live image opens the Installer and
# the Recovery, and an ordinary desktop writes the device that boots one.
#
# Whatever is passed on the right of the pipe goes straight to the program, so
# `bash -s -- --debug` is a run that changes nothing.
#
# POSIX sh, because this runs before anything of the project is on the machine,
# on whatever shell that machine happens to have. Only x86_64 is built: it is
# the only architecture Arch OS installs to.
set -eu

REPO="murkl/arch-os"

# Where the release is unpacked, and where the next run finds it again. The
# program keeps its answers, its log and the image beside its own binary, so
# starting it a second time picks up where it left off and downloads nothing
# twice.
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${HOME}/Downloads}"

info() { printf ':: %s\n' "$1"; }
fail() {
    printf ':: \033[31m%s\033[0m\n' "$1" >&2
    exit 1
}

for command_name in curl tar sha256sum; do
    command -v "$command_name" >/dev/null || fail "Missing dependency: ${command_name}"
done

# Said here rather than left to the exec at the end, where a machine of another
# shape learns it as "cannot execute binary file".
[ "$(uname -m)" = "x86_64" ] || fail "Arch OS is x86_64 only, and this machine is $(uname -m)"

# The program asks things, and through a pipe stdin is this script rather than
# the person who started it.
[ -r /dev/tty ] || fail "No terminal, run this from an interactive shell"

mkdir -p "$DOWNLOAD_DIR" || fail "Cannot write to ${DOWNLOAD_DIR}"
cd "$DOWNLOAD_DIR"

printf '\n\033[34m// Arch OS\033[0m\n'

# The asset is picked by what its name ends in rather than by the name itself,
# so renaming a download stays a change to the build and nothing here.
url="$(curl -Lfs "https://api.github.com/repos/${REPO}/releases/latest" |
    sed -n 's/.*"browser_download_url": *"\(.*\.tar\.gz\)".*/\1/p' | head -n1)" ||
    fail "Cannot reach GitHub"
[ -n "$url" ] || fail "The latest release holds no program"
name="${url##*/}"

# Written to a .part and moved into place afterwards, so a file that is there is
# a file that arrived whole — which is what makes skipping it safe.
if [ -f "$name" ]; then
    info "Present: ${name}"
else
    info "Fetching: ${name}"
    curl -Lf --progress-bar "$url" -o "${name}.part" || fail "Download failed: ${name}"
    mv "${name}.part" "$name"
fi

# The checksum ships beside the archive and names the file itself, so this is
# the check anybody would run by hand. A file that fails is thrown away rather
# than kept, so the next run fetches it again instead of skipping a broken one.
curl -Lfs "${url}.sha256" -o "${name}.sha256" || fail "Download failed: ${name}.sha256"
if ! sha256sum -c "${name}.sha256" >/dev/null 2>&1; then
    rm -f "$name" "${name}.sha256"
    fail "Checksum mismatch: ${name} was discarded, please run this again"
fi
info "Checksum is correct"

# The folder is named by the archive rather than by this script: it carries the
# version, and which version that is belongs to the build. awk rather than
# `head -n1`, which closes the pipe on tar and leaves a write error in the
# output of a run that worked.
tar -xzf "$name" || fail "Cannot unpack ${name}"
dir="$(tar -tzf "$name" | awk -F/ 'NR == 1 { print $1 }')"
[ -x "${dir}/oak" ] || fail "No program in ${name}"
info "Unpacked: ${DOWNLOAD_DIR}/${dir}"

# Started out of its own folder, because the program reads the oak.yaml beside
# its binary and keeps everything it writes there too.
cd "$dir"
exec ./oak "$@" </dev/tty

# What more than one script of this module has to agree about, sourced by Oak in
# front of every one of them. Anything a single script needs stays in that
# script; the functions a declaration calls by name are at the bottom.

# Where the program was started, which is where Oak keeps the answers, the log
# and the oak.yaml that says which version this is.
HERE="$(dirname "$MODULE_CONF")"

# Not the newest release but the one this program came out of: a binary from
# last month writing this month's image is two versions on one machine, and only
# one of them was ever tested together.
VERSION="$(sed -n 's/^version:[[:space:]]*//p' "${HERE}/oak.yaml")"

# ////////////////////////////////////////////////////////////////////////////
# SIMULATION
# ////////////////////////////////////////////////////////////////////////////

# --debug runs without touching the machine. Every task and every test opens on
# `simulating && return 0`: a task because there is nothing it may change, a
# test because a simulated run wrote nothing for it to read back.
#
# The pause holds each step on screen long enough to be read, which is what
# makes a simulated run something to watch — and what docs/screenshots.py
# photographs a run in the middle of.
#
# debugging is the bare question, for the few places that ask it without being
# a step: an answer applied to this machine, a list a page opens on.

debugging() { [ "$DEBUG" = "true" ]; }

simulating() {
    debugging || return 1
    echo "simulated"
    sleep 1
}

# ////////////////////////////////////////////////////////////////////////////
# WHAT IS WRITTEN, AND FROM WHERE
# ////////////////////////////////////////////////////////////////////////////

# Where the release this program came out of is published.
REPO="murkl/arch-os"

# The image in the download folder, named after the version rather than read out
# of a release: a machine with the file already here needs no release to name it.
image() { printf '%s/arch-os-%s-x86_64.iso' "$(download_dir)" "$VERSION"; }

# https even after a redirect, because -L would otherwise follow a 302 into
# plain http, where the answer can be anybody's - and a connect timeout, so a
# machine behind a black hole says so rather than hanging.
fetch_url() {
    curl -Lf --proto '=https' --proto-redir '=https' --connect-timeout 10 "$@"
}

# The release this program came out of, as GitHub describes it: where the image
# is and what it has to hash to, as two words. The release carries no checksum
# file - the checksum is a field of the asset, and it is the same one the
# release page prints under the download.
#
# Nothing where the release cannot be reached. The step that asked says what
# that means for it, because it is not the same answer twice.
#
# The asset is picked by what its name ends in rather than by the name itself,
# so renaming a download stays a change to the build. Each one is weighed when
# the next begins, so nothing here leans on the order GitHub writes an asset's
# fields in.
image_asset() {
    local json
    json="$(fetch_url -s --max-time 20 "https://api.github.com/repos/${REPO}/releases/tags/v${VERSION}" || true)"
    printf '%s\n' "$json" | awk '
        function weigh() {
            if (!found && url ~ /\.iso$/) { found = 1; print url, digest }
            url = ""; digest = ""
        }
        /"url": *"[^"]*\/releases\/assets\// { weigh() }
        /"digest": *"sha256:/ { digest = $0; sub(/.*sha256:/, "", digest); sub(/".*/, "", digest) }
        /"browser_download_url": *"/ { url = $0; sub(/.*: *"/, "", url); sub(/".*/, "", url) }
        END { weigh() }'
}

# ////////////////////////////////////////////////////////////////////////////
# THE YAML | Every function a declaration calls by name
# ////////////////////////////////////////////////////////////////////////////

# Whether this machine is running from a booted live image, which is the one
# machine this module does not belong on. Not "is it Arch": a device is written
# from any Linux at all.
on_live_image() {
    [ -d /run/archiso ] || grep -qs archisobasedir /proc/cmdline
}

# Where both downloads go, before there is an answer and as the value the
# question opens on: the folder this session keeps downloads in, or the one
# every desktop falls back to.
# https://specifications.freedesktop.org/basedir-spec/latest/
download_dir() {
    [ -n "$ARCH_OS_DOWNLOAD_DIR" ] && {
        printf '%s' "$ARCH_OS_DOWNLOAD_DIR"
        return 0
    }
    [ -n "${XDG_DOWNLOAD_DIR:-}" ] && {
        printf '%s' "$XDG_DOWNLOAD_DIR"
        return 0
    }
    printf '%s/Downloads' "${HOME:-$HERE}"
}

# The two ways on from an image nothing can be held against, and nothing at all
# where the release publishes a checksum: a list that comes back empty is a
# question with nothing to decide, and Oak skips the step that asked it. So an
# ordinary run never sees this page - only one where the release cannot be
# reached, or does not exist yet, which is what an image built here is.
#
# A simulated run shows it either way and asks nothing of the network: this is
# the one page of this module that is otherwise never looked at.
unverified_choices() {
    if ! debugging && [ -n "$(image_asset | cut -d' ' -f2)" ]; then
        return 0
    fi
    printf 'false\tStop and write nothing\n'
    printf 'true\tWrite it without verifying\n'
}

# The USB disks this machine has: the device path, a tab, and what a person
# picks it by. By transport rather than by anything read off the partitions - a
# disk this machine boots from is not on a USB bus, so it cannot turn up here at
# all, which is the one mistake that cannot be taken back.
list_devices() {
    lsblk -dn -o PATH,TRAN,SIZE,MODEL |
        awk '$2 == "usb" { path = $1; $1 = ""; $2 = ""; sub(/^ +/, ""); sub(/ +$/, ""); print path "\t" path "  " $0 }'
}

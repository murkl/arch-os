# shellcheck shell=bash
# What several modules of Arch OS share, loaded in front of every module.sh.
# What one task or one action needs stays in its own folder.
# https://github.com/murkl/oak/blob/main/docs/REFERENCE.md

# Under --debug only what reads still runs: a page's list, an answer applied.
debugging() { [ "$DEBUG" = "true" ]; }

# https even after a redirect, and a connect timeout instead of a hang.
fetch_url() {
    curl -Lf --proto '=https' --proto-redir '=https' --connect-timeout 10 "$@"
}

# Where the Installer builds the system and the Recovery opens it.
# shellcheck disable=SC2034
MNT=/mnt

# ////////////////////////////////////////////////////////////////////////////
# THE NETWORK
# ////////////////////////////////////////////////////////////////////////////

# Real HTTPS rather than a ping, which a captive portal answers too. Simulated,
# it is online, so the pictures of a run come out the same on every desk.
is_online() {
    debugging && return 0
    fetch_url -sI --connect-timeout 5 --max-time 10 https://archlinux.org >/dev/null
}

# The wireless card's station, or nothing where there is no card. iwd is started
# only on the live image; anywhere else it is not ours to start.
#
# iwctl colours its table and puts the reset code at the start of the first
# device row, so the colours come off before the first column is read. The
# match is remembered rather than exited on: a closed pipe fails under pipefail.
wifi_station() {
    local station=""
    compgen -G '/sys/class/ieee80211/*' >/dev/null || return 0
    if on_live_image && ! systemctl is-active -q iwd; then
        systemctl start iwd
    fi
    for _ in $(seq 10); do
        station="$(iwctl device list |
            sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\r//' |
            awk '!found && $NF == "station" { print $1; found = 1 }')"
        [ -n "$station" ] && break
        sleep 0.5 # a daemon started just now has not found the card yet
    done
    printf '%s' "$station"
}

# Joined is not yet online: the address comes a few seconds later.
wifi_online() {
    for _ in $(seq 6); do
        is_online && return 0
        sleep 2
    done
    return 1
}

# ////////////////////////////////////////////////////////////////////////////
# THE SHARING
# ////////////////////////////////////////////////////////////////////////////

# No account and no key: a POST in, the address it lives at out.
PASTE="https://paste.rs"

paste_online() {
    fetch_url -s --max-time 30 --data-binary @- "${PASTE}/" | tr -d '[:space:]'
}

# An answer written back into the file Oak reads, replacing an earlier one.
answer() {
    local tmp="${MODULE_CONF}.answer"
    grep -v "^${1}=" "$MODULE_CONF" >"$tmp" 2>/dev/null || : >>"$tmp"
    printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")" >>"$tmp"
    mv -f "$tmp" "$MODULE_CONF"
}

# ////////////////////////////////////////////////////////////////////////////
# THE RELEASE
# ////////////////////////////////////////////////////////////////////////////

# The release this program is, read from the oak.yaml beside the answer file:
# what a module fetches is what was tested with it.
REPO="murkl/arch-os"
VERSION="$(sed -n 's/^version:[[:space:]]*//p' "$(dirname "$MODULE_CONF")/oak.yaml")"

# The download of that release whose name ends in $1, and the sha256 GitHub
# publishes for it, as two words - nothing where the release is out of reach.
# Each asset is weighed when the next begins, so the field order does not matter.
release_asset() {
    local json
    json="$(fetch_url -s --max-time 20 "https://api.github.com/repos/${REPO}/releases/tags/v${VERSION}" || true)"
    printf '%s\n' "$json" | awk -v suffix="$1" '
        function weigh() {
            if (!found && url != "" && substr(url, length(url) - length(suffix) + 1) == suffix) { found = 1; print url, digest }
            url = ""; digest = ""
        }
        /"url": *"[^"]*\/releases\/assets\// { weigh() }
        /"digest": *"sha256:/ { digest = $0; sub(/.*sha256:/, "", digest); sub(/".*/, "", digest) }
        /"browser_download_url": *"/ { url = $0; sub(/.*: *"/, "", url); sub(/".*/, "", url) }
        END { weigh() }'
}

# ////////////////////////////////////////////////////////////////////////////
# THE LIVE IMAGE
# ////////////////////////////////////////////////////////////////////////////

# Either marker is enough: what the image mounts, or what it was booted with.
on_live_image() {
    [ -d /run/archiso ] || grep -qs archisobasedir /proc/cmdline
}

# The keyboard the live image was started with, which the Arch image records only
# as a loadkeys line in root's history. None there is the ordinary case.
live_keymap() {
    local keymap
    keymap="$({ grep -h 'loadkeys' /root/.bash_history /root/.zsh_history 2>/dev/null || true; } |
        tail -n1 | sed 's/.*loadkeys *//' | tr -d ' ')"
    printf '%s' "${keymap:-us}"
}

# The disk the live image runs from - also through Ventoy - which no module may
# write to.
live_disk() {
    lsblk -no PKNAME,MOUNTPOINT |
        awk '!found && $1 != "" && $2 ~ /^\/run\/archiso/ { print "/dev/" $1; found = 1 }'
}

# Whole disks by type rather than by major number, chosen by size and model.
list_disks() {
    lsblk -dn -o PATH,TYPE,SIZE,MODEL | awk -v live="$(live_disk)" '
        $2 != "disk" || $1 == live || $1 ~ /^\/dev\/zram/ { next }
        { path = $1; $1 = ""; $2 = ""; sub(/^ +/, ""); sub(/ +$/, ""); printf "%s\t%s  %s\n", path, path, $0 }'
}

# ////////////////////////////////////////////////////////////////////////////
# THE SYSTEM ON THE DISK
# ////////////////////////////////////////////////////////////////////////////

# The one kernel Arch OS installs, and so the one the Recovery puts back.
# shellcheck disable=SC2034
KERNEL=linux-zen

# Every file sbctl keeps is signed, and there is one. Read off its list, because
# `sbctl verify` answers 0 whatever it found.
boot_chain_signed() {
    local files
    files="$(arch-chroot "$1" sbctl list-files --json)" || return 1
    if ! grep -q '"is_signed": true' <<<"$files"; then
        echo "sbctl keeps no signed file" >&2
        return 1
    fi
    if grep -q '"is_signed": false' <<<"$files"; then
        echo "sbctl keeps files that are not signed: ${files}" >&2
        return 1
    fi
}

# A partition of a disk as the Installer lays it out: nvme0n1 gets a p.
part_of() {
    local sep=""
    [[ "$1" =~ [0-9]$ ]] && sep="p"
    printf '%s%s%s' "$1" "$sep" "$2"
}

# The btrfs layout, subvolume and mount point - see docs/REFERENCE.md.
# shellcheck disable=SC2034
BTRFS_OPTS="defaults,noatime,compress=zstd"

btrfs_subvolumes() {
    printf '%s\t%s\n' \
        @ / \
        @home /home \
        @snapshots /.snapshots \
        @log /var/log \
        @cache /var/cache \
        @tmp /var/tmp \
        @libvirt /var/lib/libvirt/images
}

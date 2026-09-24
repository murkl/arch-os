# shellcheck shell=bash
# What the modules of Arch OS have to agree about with each other, loaded by Oak
# in front of every script of every one of them and before that module's own
# module.sh. What only one module needs stays in that module.
#
# https://github.com/murkl/oak/blob/main/docs/REFERENCE.md

# Whether this run only pretends to work. Oak starts no task under --debug, so
# this is for the few places that still run there and must not touch the
# machine: an answer applied to it, a list a page opens on, a task that
# simulates itself.
debugging() { [ "$DEBUG" = "true" ]; }

# Everything a module downloads, https even after a redirect: -L on its own
# would follow a 302 into plain http, where the answer is whoever is on the wire.
# A connect timeout, so a machine behind a black hole says so rather than hangs.
fetch_url() {
    curl -Lf --proto '=https' --proto-redir '=https' --connect-timeout 10 "$@"
}

# ////////////////////////////////////////////////////////////////////////////
# THE NETWORK
# ////////////////////////////////////////////////////////////////////////////

# Real HTTPS to a host every module needs anyway, not a ping - a captive portal
# answers pings too. Only the headers: it is asked every few seconds for the
# line in the header, and the answer is whether it came, not what it said.
is_online() {
    fetch_url -sI --connect-timeout 5 --max-time 10 https://archlinux.org >/dev/null
}

# The line in the header - see status: in oak.yaml. A simulated run shows what a
# connected machine shows rather than whatever the desk it is read on happens
# to be, so the pictures of it come out the same on every run.
header_online() { debugging || is_online; }

# Everything a wireless network needs, started where it is not running yet: the
# Recovery's own partition starts none of it on its own, since what it repairs
# may be the network, and brings it up the moment somebody asks for one. The
# Arch ISO runs all of it from boot, and anywhere else is not ours to start.
# networkd answers DHCP on the card and on a cable, resolved answers names.
network_up() {
    on_live_image || return 0
    systemctl is-active -q iwd && return 0
    systemctl start systemd-networkd systemd-resolved iwd
}

# The first station is taken rather than asked for: a machine with two wireless
# cards is rare enough that a prompt would cost everyone else a question. A
# daemon started just now has not found the card yet, so it is given a few
# seconds to.
#
# iwctl draws a table for a human: it is coloured, and it puts the reset
# sequence at the start of the line that follows a coloured one - which is the
# first device row. Read as it comes, the first column of that row is the escape
# and not a name, and a machine with one card, which is every laptop, hands the
# whole of the wireless flow a device called "\e[0m". So the colours come off
# first, exactly as they do in the scan below.
#
# The match is remembered rather than exited on: a filter that closes the pipe
# leaves iwctl with a write error, and under pipefail that is a failed hook
# instead of an answer.
wlan_station() {
    local station=""
    network_up
    for _ in $(seq 10); do
        station="$(iwctl device list |
            sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\r//' |
            awk '!found && $NF == "station" { print $1; found = 1 }')"
        [ -n "$station" ] && break
        sleep 0.5
    done
    printf '%s' "$station"
}

# The networks in range, one SSID per line, strongest first.
#
# The scan is fired here rather than by Oak because iwctl returns as soon as it
# has started one: the wait belongs beside the command that needs it. And it is
# a wait for the card rather than a fixed pause - a list read while the radio is
# still going round the channels is short rather than wrong, and a card that has
# finished in half a second should not cost three.
wlan_networks() {
    local state
    iwctl station "$WLAN_DEVICE" scan || true
    for _ in $(seq 20); do
        sleep 0.5
        # Into a variable first: a grep that stops reading leaves iwctl with a
        # write error, and under pipefail that is a failed hook instead of an
        # answer.
        state="$(iwctl station "$WLAN_DEVICE" show | sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\r//')"
        grep -qE '^[[:space:]]*Scanning[[:space:]]+no([[:space:]]|$)' <<<"$state" && break
    done

    # iwctl's table is coloured, drawn for a human, and an SSID may hold
    # spaces, so the columns can't be split on whitespace. They're padded apart
    # instead, which makes "two or more spaces" the only separator that doesn't
    # corrupt a name like "Coffee Bar Free".
    iwctl station "$WLAN_DEVICE" get-networks |
        sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\r//' |
        awk '
            # iwctl brackets its header with two rules; the networks come after.
            /^[[:space:]]*-+[[:space:]]*$/ { rules++; next }
            rules < 2 { next }
            {
                line = $0
                # The connected network is marked with ">"; it is still a choice.
                sub(/^[[:space:]]*>?[[:space:]]*/, "", line)
                sub(/[[:space:]]+$/, "", line)
                if (line == "") next
                # Columns are padded apart: name, security, signal.
                split(line, col, /[[:space:]][[:space:]]+/)
                name = col[1]
                if (name == "" || seen[name]++) next
                print name
            }
        '
}

# The one place here a secret reaches a command line, and iwctl's only way in
# without one: unasked, it puts the question to an agent on the terminal the
# interface is drawing on. A live image with one account, for one second, for a
# passphrase that is written down nowhere and is not the disk password.
#
# Where there is nothing to ask whether it carries traffic yet, the join waits
# for that here: a card that has joined still needs its address, and the line in
# the header is read again the moment this returns.
wlan_join() {
    if ! iwctl --passphrase "$WLAN_PASSPHRASE" station "$WLAN_DEVICE" connect "$WLAN_SSID"; then
        # What iwctl says when it refuses is a row of its own table and goes to
        # stdout, which here is the hook's answer rather than anything anybody
        # reads. So the reason is said once, in a sentence, on the channel a
        # failure is read from - and it names the passphrase, which is what it
        # is nearly every time.
        echo "${WLAN_SSID} did not accept that passphrase, or it is no longer in range." >&2
        return 1
    fi
    for _ in $(seq 20); do
        is_online && return 0
        sleep 0.5
    done
    return 0
}

# ////////////////////////////////////////////////////////////////////////////
# THE RELEASE
# ////////////////////////////////////////////////////////////////////////////

# Where this project is published, and which release this program is: the
# version in the oak.yaml beside it rather than the newest one, so what a module
# fetches is what was tested together with it. Oak keeps the answer file beside
# oak.yaml, which is how a script finds it.
REPO="murkl/arch-os"
VERSION="$(sed -n 's/^version:[[:space:]]*//p' "$(dirname "$MODULE_CONF")/oak.yaml")"

# A download of that release as GitHub describes it: where it is and what it has
# to hash to, as two words - and nothing where the release cannot be reached.
# The release carries no checksum file: the checksum is a field of the asset,
# the same one the release page prints under the download. The step that asked
# says what nothing means for it, because it is not the same answer twice.
#
# Picked by what its name ends in rather than by the name itself, so renaming a
# download stays a change to the build. Each asset is weighed when the next
# begins, so nothing here leans on the order GitHub writes an asset's fields in.
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

# Whether this is a booted Arch Linux live image, which the Installer and the
# Recovery belong on and Create boot medium does not. Two markers, because
# either on its own is enough: /run/archiso is what the image mounts,
# archisobasedir is what it was booted with.
on_live_image() {
    [ -d /run/archiso ] || grep -qs archisobasedir /proc/cmdline
}

# And Arch on top of them, because an image built the same way by somebody else
# is not the system Arch OS installs or repairs.
arch_live() {
    on_live_image || return 1
    grep -qs '^ID=arch$' /etc/os-release
}

# The keyboard the live image was started with. The Arch image records it only
# as the loadkeys command in root's shell history, and finding nothing there is
# the ordinary case - an image nobody ran loadkeys on is on the American
# layout - so the grep must not make a failure of it: pipefail would carry that
# out of the whole lookup.
live_keymap() {
    local keymap
    keymap="$({ grep -h 'loadkeys' /root/.bash_history /root/.zsh_history 2>/dev/null || true; } |
        tail -n1 | sed 's/.*loadkeys *//' | tr -d ' ')"
    printf '%s' "${keymap:-us}"
}

# The disk the live image is running from, or nothing where that cannot be read.
# Every part of the image is reached through it for as long as the run lasts, so
# it is the one disk no module may write to or open. Read off the mount table
# rather than off the boot medium's name, because that is also how an image
# booted through Ventoy says which disk it came from.
live_disk() {
    lsblk -no PKNAME,MOUNTPOINT |
        awk '!found && $1 != "" && $2 ~ /^\/run\/archiso/ { print "/dev/" $1; found = 1 }'
}

# Whole disks only, asked of lsblk by what a device is rather than by the major
# number it was given: SATA, NVMe, eMMC, SD and a virtual disk are five numbers,
# one of which the kernel hands out at random - and a disk nobody can choose is
# a machine nobody can install onto or repair.
#
# Nobody picks between /dev/sda and /dev/sdb by name, so the size and the model
# are what it is chosen by.
list_disks() {
    lsblk -dn -o PATH,TYPE,SIZE,MODEL | awk -v live="$(live_disk)" '
        $2 != "disk" || $1 == live || $1 ~ /^\/dev\/zram/ { next }
        { path = $1; $1 = ""; $2 = ""; sub(/^ +/, ""); sub(/ +$/, ""); printf "%s\t%s  %s\n", path, path, $0 }'
}

# ////////////////////////////////////////////////////////////////////////////
# THE KERNEL
# ////////////////////////////////////////////////////////////////////////////

# The one kernel Arch OS installs, and so the one the Recovery puts back.
# shellcheck disable=SC2034
KERNEL=linux-zen

# ////////////////////////////////////////////////////////////////////////////
# THE SIGNED BOOT CHAIN
# ////////////////////////////////////////////////////////////////////////////

# Whether every file sbctl keeps in the system mounted at $1 is signed, and
# there is a file at all - what the Installer signs and the Recovery signs again
# after a rebuild. Read out of sbctl's own list, because `sbctl verify` answers
# 0 whatever it found, and `sbctl sign-all` over an empty database signs nothing
# without a word. Either leaves a machine that Secure Boot refuses to start.
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

# ////////////////////////////////////////////////////////////////////////////
# THE DISK LAYOUT
# ////////////////////////////////////////////////////////////////////////////

# Names a partition of a disk as the Installer lays it out: the EFI system
# partition first, the root second - see docs/REFERENCE.md. A disk whose name
# ends in a digit (nvme0n1, mmcblk0, loop0) gets a p between it and the number.
part_of() {
    local sep=""
    [[ "$1" =~ [0-9]$ ]] && sep="p"
    printf '%s%s%s' "$1" "$sep" "$2"
}

# How Arch OS mounts btrfs, and what it lays down: subvolume, a tab, then where
# it belongs. The Installer creates every one of them and the Recovery mounts
# every one of them. Why the four under /var are separate: docs/REFERENCE.md
#
# Read by the modules' scripts, which shellcheck reads one at a time, so the
# option string looks unused here.
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

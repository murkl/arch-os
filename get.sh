#!/usr/bin/env sh
# Arch OS, from one command:
#
#   curl -Ls bit.ly/arch-os | bash
#
# It does one of two things, and where it runs decides which. On a booted Arch
# live image there is a machine to install onto, so it fetches the latest
# release and starts the installer. Anywhere else there is not, so it fetches
# the latest image and writes it to a USB device — which turns this machine into
# the one that makes the stick that boots the other case.
#
# So the same command is the right one to run twice: once on the desktop to get
# a boot device, and once on the machine that device booted.
#
# MODE=install|create picks the half by hand, and DEBUG=true keeps both off the
# hardware — nothing is written to a device, and the installer it starts
# simulates every step. Together they are how either half is tried from a
# desktop without a spare machine.
#
# POSIX sh on purpose: this is the one part of the project that runs before
# anything of it has been downloaded, on whatever shell the machine happens to
# have. Nothing beyond what an Arch image and a Linux desktop both already
# ship — curl, tar, coreutils, util-linux.
set -eu

# ─── Where a release comes from ──────────────────────────────────────────────

# What an artefact is called is deliberately not written down here. The release
# is asked what it holds and the assets are picked by extension, so renaming a
# download stays a change to the Makefile that builds it.
REPO="murkl/arch-os"
RELEASE_API="https://api.github.com/repos/${REPO}/releases/latest"

# Everything downloaded lands here and is reused on a second run rather than
# fetched twice — a wrong device, a lost connection or a crashed installer costs
# the download once.
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${HOME}/Downloads}"

# install, create, or auto: worked out from where this runs.
MODE="${MODE:-auto}"

# Touch no hardware: no device is written, and the installer simulates every
# step (see setup/util.sh, which reads the same variable).
DEBUG="${DEBUG:-false}"

# ─── Output ──────────────────────────────────────────────────────────────────

title() { printf '\n\033[34m// %s\033[0m\n' "$1"; }
info() { printf ':: %s\n' "$1"; }
ok() { printf ':: \033[32m%s\033[0m\n' "$1"; }
warn() { printf ':: \033[33m%s\033[0m\n' "$1"; }
fail() {
    printf ':: \033[31m%s\033[0m\n' "$1" >&2
    exit 1
}

usage() {
    cat <<EOF
Arch OS — https://github.com/${REPO}

  curl -Ls bit.ly/arch-os | bash

On a booted Arch live image: fetches the latest release and starts the
installer. Anywhere else: fetches the latest image and writes it to a USB
device, so this machine can make the one that boots it.

  MODE=install|create   pick the half by hand instead of by where it runs
  DEBUG=true            write nothing: no device, and a simulated installation
  DOWNLOAD_DIR=<dir>    where downloads are kept (default ${DOWNLOAD_DIR})
EOF
}

# ─── What this machine is ────────────────────────────────────────────────────

# An Arch live image, the official one or ours — they are built the same way.
# The initramfs hook that mounted the image leaves /run/archiso behind, and the
# kernel command line names the image it booted. Either one on its own is
# enough, and a shell that lost the first still has the second.
is_live() {
    [ -d /run/archiso ] || grep -qs archisobasedir /proc/cmdline
}

require() {
    for command_name in "$@"; do
        command -v "$command_name" >/dev/null || fail "Missing dependency: ${command_name}"
    done
}

# Unmounting and writing a device need root, and how one gets there depends on
# who is asking: a desktop runs this as a person and reaches for sudo, a root
# shell has nothing to escalate and may not have sudo installed at all.
as_root() {
    if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

# ─── Downloads ───────────────────────────────────────────────────────────────

# The download URL of the one asset of the latest release whose name ends the
# given way. Matched literally rather than by pattern, so ".iso" is the image
# and never the checksum file beside it.
asset_url() {
    printf '%s' "$RELEASE" |
        grep -o '"browser_download_url": *"[^"]*"' |
        sed 's/.*: *"//; s/"$//' |
        while IFS= read -r candidate; do
            case "$candidate" in *"$1") printf '%s\n' "$candidate" ;; esac
        done |
        head -n1
}

# Fetches a URL into DOWNLOAD_DIR under the name it ends in, and leaves what is
# already there alone. Written to a .part first and moved into place after, so
# a file that is there is a file that arrived whole — an interrupted download
# is never mistaken for one on the next run.
download() {
    download_name="${1##*/}"
    if [ -f "${DOWNLOAD_DIR}/${download_name}" ]; then
        info "Present: ${download_name}"
        return 0
    fi
    info "Fetching: ${download_name}"
    curl -Lf --progress-bar "$1" -o "${DOWNLOAD_DIR}/${download_name}.part" ||
        fail "Download failed: $1"
    mv "${DOWNLOAD_DIR}/${download_name}.part" "${DOWNLOAD_DIR}/${download_name}"
}

# Every release artefact ships a .sha256 beside it holding the file's own name,
# so an image is checked here exactly the way it would be checked by hand. A
# file that fails is thrown away rather than kept: what is left in
# DOWNLOAD_DIR is only ever something that verified, and the next run fetches
# it again instead of failing on it forever.
verify() {
    download "${1}.sha256"
    verify_name="${1##*/}"
    info "Verifying: ${verify_name}"
    if ! (cd "$DOWNLOAD_DIR" && sha256sum -c "${verify_name}.sha256" >/dev/null 2>&1); then
        rm -f "${DOWNLOAD_DIR}/${verify_name}" "${DOWNLOAD_DIR}/${verify_name}.sha256"
        fail "Checksum mismatch: ${verify_name} was discarded, please run this again"
    fi
    ok "Checksum is correct"
}

# ─── Install: the machine this runs on becomes Arch OS ───────────────────────

install_mode() {
    require curl tar sha256sum
    [ "$(id -u)" -eq 0 ] || fail "The installer needs root"

    title "Arch OS Installer"
    tarball_url="$(asset_url .tar.gz)"
    [ -n "$tarball_url" ] || fail "The latest release holds no installer"
    download "$tarball_url"
    verify "$tarball_url"

    # The folder is named by the archive rather than by this script: it carries
    # a version, and which version that is belongs to the build.
    tarball="${DOWNLOAD_DIR}/${tarball_url##*/}"
    tarball_dir="${DOWNLOAD_DIR}/$(tar -tzf "$tarball" | head -n1 | cut -d/ -f1)"
    tar -xzf "$tarball" -C "$DOWNLOAD_DIR" || fail "Could not unpack ${tarball}"
    [ -x "${tarball_dir}/installer" ] || fail "No installer in ${tarball}"
    ok "Unpacked: ${tarball_dir}"

    # Started out of its own folder, because the runtime looks for the tree it
    # runs beside its own binary, and because its answers and its log land in
    # the working directory — so leaving the installer and running this again
    # picks up exactly where it left off.
    #
    # stdin is this script itself when the command arrives through a pipe, so
    # the interface is handed the terminal instead. Without it, it reads an
    # exhausted pipe and quits the moment it starts.
    cd "$tarball_dir"
    exec ./installer </dev/tty
}

# ─── Create: this machine makes the device that boots the other one ──────────

# The USB disks this machine has, one per line: the device path, a tab, and
# what a person picks it by. Nobody knows their stick as /dev/sdb — they know
# it by its size and the name printed on it.
usb_disks() {
    lsblk -dn -o PATH,TRAN,SIZE,MODEL |
        awk '$2 == "usb" { path = $1; $1 = ""; $2 = ""; sub(/^ +/, ""); print path "\t" $0 }'
}

create_mode() {
    require curl sha256sum lsblk awk dd
    [ "$(id -u)" -eq 0 ] || require sudo

    title "Arch OS Image"
    iso_url="$(asset_url .iso)"
    [ -n "$iso_url" ] || fail "The latest release holds no image"
    download "$iso_url"
    verify "$iso_url"
    iso="${DOWNLOAD_DIR}/${iso_url##*/}"

    title "Target Device"
    disks="$(usb_disks)"
    [ -n "$disks" ] || fail "No USB device found — plug one in and run this again"
    printf '%s\n' "$disks" | awk -F'\t' '{ printf "  %d) %s  %s\n", NR, $1, $2 }'

    disk_count="$(printf '%s\n' "$disks" | wc -l)"
    printf ':: Device number [1-%s]: ' "$disk_count"
    read -r choice </dev/tty
    case "$choice" in
    '' | *[!0-9]*) fail "Not a device number: ${choice}" ;;
    esac
    [ "$choice" -ge 1 ] && [ "$choice" -le "$disk_count" ] || fail "No such device: ${choice}"
    device="$(printf '%s\n' "$disks" | sed -n "${choice}p" | cut -f1)"
    [ -b "$device" ] || fail "Not a block device: ${device}"

    title "Write Device"
    printf ':: Everything on %s will be erased. Continue? [y/N]: ' "$device"
    read -r confirm </dev/tty
    case "$confirm" in
    [Yy]*) ;;
    *)
        warn "Cancelled"
        exit 0
        ;;
    esac

    if [ "$DEBUG" = "true" ]; then
        warn "Simulated: ${iso##*/} would be written to ${device}"
    else
        # A mounted partition would be written out from under its own
        # filesystem. Lazy as the fallback: a file manager holding the stick
        # open is the usual reason a plain umount refuses.
        lsblk -nro MOUNTPOINT "$device" | while IFS= read -r mountpoint; do
            [ -n "$mountpoint" ] || continue
            as_root umount "$mountpoint" || as_root umount -l "$mountpoint"
        done
        if lsblk -nro MOUNTPOINT "$device" | grep -q .; then
            fail "Could not unmount every partition of ${device}"
        fi

        as_root dd if="$iso" of="$device" bs=4M status=progress oflag=sync ||
            fail "Writing ${device} failed"
        ok "Bootable device created"
    fi

    title "Finished"
    info "Remove ${device} and boot the machine you want Arch OS on from it."
    info "The installer starts on its own."
}

# ─── Main ────────────────────────────────────────────────────────────────────

case "${1:-}" in
-h | --help)
    usage
    exit 0
    ;;
esac

# Both halves ask something, and the answer cannot come from stdin: through a
# pipe that is this script. Said here once, before anything is downloaded.
[ -r /dev/tty ] || fail "No terminal — run this from an interactive shell"

mkdir -p "$DOWNLOAD_DIR" || fail "Cannot write to ${DOWNLOAD_DIR}"
trap 'rm -f "${DOWNLOAD_DIR}"/*.part; exit 130' INT TERM HUP

if [ "$MODE" = "auto" ]; then
    if is_live; then MODE="install"; else MODE="create"; fi
fi

title "Arch OS"
case "$MODE" in
install) info "Live environment — installing Arch OS on this machine" ;;
create) info "No live environment — creating a bootable Arch OS device" ;;
*) fail "MODE is install, create or auto — not ${MODE}" ;;
esac
if [ "$DEBUG" = "true" ]; then
    warn "DEBUG: nothing will be written to any hardware"
fi

RELEASE="$(curl -Lfs "$RELEASE_API")" || fail "Cannot reach GitHub"
[ -n "$RELEASE" ] || fail "No release found for ${REPO}"

case "$MODE" in
install) install_mode ;;
create) create_mode ;;
esac

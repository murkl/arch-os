#!/usr/bin/env sh
# Writes the latest Arch OS ISO to a USB device, from any Linux:
#
#   curl -fsSL https://raw.githubusercontent.com/murkl/arch-os/main/get.sh | sh
#
# POSIX sh, because it runs on whatever shell the machine has.
set -eu

# ////////////////////////////////////////////////////////////////////////////
# VARIABLES
# ////////////////////////////////////////////////////////////////////////////

REPO="murkl/arch-os"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${XDG_DOWNLOAD_DIR:-${HOME}/Downloads}}"

# ////////////////////////////////////////////////////////////////////////////
# FUNCTIONS
# ////////////////////////////////////////////////////////////////////////////

title() { printf '\n\033[34m// %s\033[0m\n' "$1"; }
info() { printf ':: %s\n' "$1"; }
ok() { printf ':: \033[32m%s\033[0m\n' "$1"; }
fail() {
    printf ':: \033[31m%s\033[0m\n' "$1" >&2
    exit 1
}

# Through a pipe stdin is this script, so every answer comes from the terminal.
ask() {
    printf ':: %s [y/N] ' "$1"
    read -r reply </dev/tty
    case "$reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# https even after a redirect: -L alone would follow a 302 into plain http.
fetch() { curl --proto '=https' --proto-redir '=https' --connect-timeout 10 "$@"; }

# Root only for the three commands that write.
as_root() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo -- "$@"; fi; }

# Swap, or a mount anywhere but where a stick is put: the running system uses it.
in_use() {
    lsblk -nro MOUNTPOINTS "$1" | awk '
        { n = split($0, mounts, /\\x0a/) }
        {
            for (i = 1; i <= n; i++)
                if (mounts[i] != "" && mounts[i] !~ /^\/(run\/media|media|mnt)(\/|$)/) found = 1
        }
        END { exit !found }'
}

# ////////////////////////////////////////////////////////////////////////////
# MAIN
# ////////////////////////////////////////////////////////////////////////////

for command_name in curl awk sha256sum lsblk dd; do
    command -v "$command_name" >/dev/null || fail "Missing dependency: ${command_name}"
done
[ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null || fail "Missing dependency: sudo"
[ -r /dev/tty ] || fail "No terminal, run this from an interactive shell"

title "Arch OS ISO"

# The ISO and its sha256 out of GitHub's description of the latest release:
# one field to a line however the JSON is laid out, and each asset weighed when
# the next one begins, whatever order its fields come in.
release="$(fetch -Lfs "https://api.github.com/repos/${REPO}/releases/latest")" || fail "Cannot reach GitHub"
asset="$(printf '%s\n' "$release" | tr ',' '\n' | awk '
    function weigh() {
        if (!found && url ~ /\.iso$/) { found = 1; print url, digest }
        url = ""; digest = ""
    }
    /"url": *"[^"]*\/releases\/assets\// { weigh() }
    /"digest": *"sha256:/ { digest = $0; sub(/.*sha256:/, "", digest); sub(/".*/, "", digest) }
    /"browser_download_url": *"/ { url = $0; sub(/.*: *"/, "", url); sub(/".*/, "", url) }
    END { weigh() }')"
[ -n "$asset" ] || fail "The latest release holds no ISO"
url="${asset%% *}"
digest="${asset##* }"
name="${url##*/}"
info "File: ${DOWNLOAD_DIR}/${name}"

title "Download"

mkdir -p "$DOWNLOAD_DIR" || fail "Cannot write to ${DOWNLOAD_DIR}"
cd "$DOWNLOAD_DIR"

# Into a .part first, so a file that is there arrived whole.
if [ -f "$name" ]; then
    info "Present, not downloaded again"
else
    fetch -Lf --retry 3 --progress-bar "$url" -o "${name}.part" || fail "Download failed: ${name}"
    mv "${name}.part" "$name"
    ok "Downloaded"
fi

title "Checksum"

# Asked rather than thrown away: an ISO built here differs on purpose.
if [ -z "$digest" ]; then
    ask "The release publishes no checksum for ${name}. Write it anyway?" || fail "Nothing written"
elif printf '%s  %s\n' "$digest" "$name" | sha256sum -c - >/dev/null 2>&1; then
    ok "Checksum is correct"
else
    ask "${name} does not match its checksum. Write it anyway?" ||
        fail "Nothing written. Delete ${DOWNLOAD_DIR}/${name} to download it again"
fi

title "USB Device"

devices=""
for device in $(lsblk -dnpr -o NAME,TRAN | awk '$2 == "usb" { print $1 }'); do
    in_use "$device" || devices="${devices} ${device}"
done
[ -n "$devices" ] || fail "No USB device the running system leaves free"

i=0
for device in $devices; do
    i=$((i + 1))
    printf '   %s) %s  %s\n' "$i" "$device" "$(lsblk -dno SIZE,MODEL "$device")"
done
printf ':: Device (1-%s): ' "$i"
read -r choice </dev/tty

target=""
i=0
for device in $devices; do
    i=$((i + 1))
    [ "$i" = "$choice" ] && target="$device"
done
[ -n "$target" ] || fail "No device ${choice}"
shown="$(lsblk -dno SIZE,MODEL "$target")"

title "Write"

ask "Erase ${target} (${shown}) and write ${name} to it?" || fail "Nothing written"

# Held to what was shown, right before the write: /dev/sdb names a stick only
# while it is plugged in.
if [ "$(lsblk -dno TRAN "$target" 2>/dev/null)" != usb ] || [ "$(lsblk -dno SIZE,MODEL "$target")" != "$shown" ]; then
    fail "${target} is not the device shown, nothing written"
fi
[ "$(lsblk -bdno SIZE "$target")" -ge "$(wc -c <"$name")" ] || fail "${target} is smaller than ${name}"

# A file manager still holding the stick open is why a plain umount refuses.
# Whatever stays mounted is named by the check after the loop.
lsblk -nlo MOUNTPOINT "$target" | while IFS= read -r mountpoint; do
    [ -z "$mountpoint" ] || as_root umount "$mountpoint" || as_root umount -l "$mountpoint" || true
done
[ -z "$(lsblk -nlo MOUNTPOINT "$target" | tr -d '\n')" ] || fail "${target} is still mounted"

# The Wiki's flags: oflag=direct makes the progress what the drive has taken,
# conv=fsync flushes the rest before dd returns. A hybrid ISO already carries
# its partition table and both boot paths.
# https://wiki.archlinux.org/title/USB_flash_installation_medium
as_root dd if="$name" of="$target" bs=4M status=progress conv=fsync oflag=direct || fail "Writing ${target} failed"
as_root blockdev --rereadpt "$target" 2>/dev/null || true

title "Finished"

ok "${target} starts Arch OS, remove it or restart from it"

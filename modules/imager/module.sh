# What several scripts of Create boot medium share, sourced in front of each
# after oak.sh. The functions the yaml calls by name are at the bottom.

# Where the program was started, which is where Oak keeps the answers.
HERE="$(dirname "$MODULE_CONF")"

# The image, named after the version: a machine that has it needs no release.
image() { printf '%s/arch-os-%s-x86_64.iso' "$(download_dir)" "$VERSION"; }

# The checksum beside it, as `sha256sum -c` reads it. The download writes it or
# takes it away, so the network is read once.
checksum() { printf '%s.sha256' "$(image)"; }

# Root for one command, only in the step that writes: a root process would
# leave two gigabytes in somebody's home that only root can delete. The password
# typed into the interface goes to sudo on stdin; -k asks every time, -p '' keeps
# the prompt out of the log, and -n makes sure a sudo that needs none never asks.
as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif [ "$ARCH_OS_IMAGE_SUDO" = "true" ]; then
        printf '%s\n' "$ARCH_OS_IMAGE_PASSWORD" | sudo -S -k -p '' -- "$@"
    else
        sudo -n -- "$@"
    fi
}

# ////////////////////////////////////////////////////////////////////////////
# THE YAML | Every function a declaration calls by name
# ////////////////////////////////////////////////////////////////////////////

# This session's download folder, or the one every desktop falls back to.
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

# The USB disks, by transport, without the ones the running system is on: a
# system can live on a USB disk too, and writing over it cannot be taken back.
list_devices() {
    local path shown
    while IFS=$'\t' read -r path shown; do
        in_system_use "$path" && continue
        printf '%s\t%s\n' "$path" "$shown"
    done < <(lsblk -dn -o PATH,TRAN,SIZE,MODEL |
        awk '$2 == "usb" { path = $1; $1 = ""; $2 = ""; sub(/^ +/, ""); sub(/ +$/, ""); print path "\t" path "  " $0 }')
}

# Something of the running system on that disk: swap, or a mount anywhere but
# where a stick is put. Raw output joins two mount points with an escaped newline.
in_system_use() {
    lsblk -nro MOUNTPOINTS "$1" | awk '
        { n = split($0, mounts, /\\x0a/) }
        { for (i = 1; i <= n; i++) if (mounts[i] != "" && mounts[i] !~ /^\/(run\/media|media|mnt)(\/|$)/) found = 1 }
        END { exit !found }'
}

# Whether the write needs a password: not as root, nor where a sudo rule says so.
# -k ignores a password sudo remembers now and will have forgotten by the write.
needs_password() {
    if [ "$(id -u)" -eq 0 ] || sudo -nk true 2>/dev/null; then echo false; else echo true; fi
}

# The password tried on sudo before it is taken: a command that does nothing.
sudo_accepts() {
    debugging && return 0
    as_root true
}

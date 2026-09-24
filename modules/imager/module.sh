# What more than one script of this module has to agree about, sourced by Oak in
# front of every one of them. Anything a single script needs stays in that
# script; the functions a declaration calls by name are at the bottom.

# Where the program was started, which is where Oak keeps the answers and the
# log. Which release this is, and where it is published, is oak.sh's.
HERE="$(dirname "$MODULE_CONF")"

# ////////////////////////////////////////////////////////////////////////////
# WHAT IS WRITTEN, AND FROM WHERE
# ////////////////////////////////////////////////////////////////////////////

# The image in the download folder, named after the version rather than read out
# of a release: a machine with the file already here needs no release to name it.
image() { printf '%s/arch-os-%s-x86_64.iso' "$(download_dir)" "$VERSION"; }

# What that release publishes the image has to hash to, beside it in the form
# `sha256sum -c` reads. The download writes it, or takes it away where there is
# none to be had, and the check after it goes by this file alone: the network
# is read once, so the download and the check cannot disagree about whether
# there was a checksum.
checksum() { printf '%s.sha256' "$(image)"; }

# ////////////////////////////////////////////////////////////////////////////
# ROOT, FOR THE WRITE
# ////////////////////////////////////////////////////////////////////////////

# This module runs as whoever started it, on somebody's own machine, where a
# root process leaves two gigabytes in their home that only root can delete
# again. So root is taken for one command at a time, and only in the step that
# writes the device.
#
# Where sudo wants a password, it is the one typed into the interface, handed to
# sudo on stdin, so the screen is never handed over for a prompt. -k asks for it
# every time rather than leaning on a credential sudo may have forgotten since,
# and -p '' keeps the prompt it no longer needs out of the log. The commands
# this wraps read nothing from stdin, which is left holding the rest of the pipe.
# Where it wants none, -n makes sure it never stops to ask.
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

# The USB disks this machine has: the device path, a tab, and what a person
# picks it by. By transport rather than by anything read off the partitions, and
# without the ones the running system is on - a system can live on a USB disk
# too, and writing over it is the one mistake that cannot be taken back.
list_devices() {
    local path shown
    while IFS=$'\t' read -r path shown; do
        in_system_use "$path" && continue
        printf '%s\t%s\n' "$path" "$shown"
    done < <(lsblk -dn -o PATH,TRAN,SIZE,MODEL |
        awk '$2 == "usb" { path = $1; $1 = ""; $2 = ""; sub(/^ +/, ""); sub(/ +$/, ""); print path "\t" path "  " $0 }')
}

# Whether the running system has something on that disk: swap, or a file system
# mounted anywhere but where a stick is put - under /run/media by the desktop,
# under /media or /mnt by hand. Raw output, where a partition mounted twice has
# its mount points joined by an escaped newline.
in_system_use() {
    lsblk -nro MOUNTPOINTS "$1" | awk '
        { n = split($0, mounts, /\\x0a/) }
        { for (i = 1; i <= n; i++) if (mounts[i] != "" && mounts[i] !~ /^\/(run\/media|media|mnt)(\/|$)/) found = 1 }
        END { exit !found }'
}

# Whether writing the device needs a password: not as root, and not where a sudo
# rule lets this account do without one. -k leaves out a password sudo still
# remembers from a terminal a minute ago - it will have forgotten it by the time
# the download is done.
needs_password() {
    if [ "$(id -u)" -eq 0 ] || sudo -nk true 2>/dev/null; then echo false; else echo true; fi
}

# The password, tried on sudo before it is taken: a command that does nothing,
# as root. A simulated run is on somebody's own machine, whose sudo is not ours
# to try.
sudo_accepts() {
    debugging && return 0
    as_root true
}

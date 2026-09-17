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

# --debug runs without touching the machine: a task opens with `simulating &&
# return 0`, a test with `debugging && return 0`. The pause is the difference —
# it holds a step on screen, and a test is not a step anybody is watching.

debugging() { [ "$DEBUG" = "true" ]; }

simulating() {
    debugging || return 1
    echo "simulated"
    sleep 1
}

# ////////////////////////////////////////////////////////////////////////////
# WHAT IS WRITTEN, AND FROM WHERE
# ////////////////////////////////////////////////////////////////////////////

# The image in the download folder, named after the version rather than read out
# of a release: a machine with the file already here needs no network at all.
image() { printf '%s/arch-os-%s-x86_64.iso' "$(download_dir)" "$VERSION"; }

# The checksum published beside it, carrying the image's own name - so
# `sha256sum -c` in that folder is the check anybody would run by hand.
checksum() { printf '%s.sha256' "$(image)"; }

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

# The USB disks this machine has: the device path, a tab, and what a person
# picks it by. By transport rather than by anything read off the partitions - a
# disk this machine boots from is not on a USB bus, so it cannot turn up here at
# all, which is the one mistake that cannot be taken back.
list_devices() {
    lsblk -dn -o PATH,TRAN,SIZE,MODEL |
        awk '$2 == "usb" { path = $1; $1 = ""; $2 = ""; sub(/^ +/, ""); sub(/ +$/, ""); print path "\t" path "  " $0 }'
}

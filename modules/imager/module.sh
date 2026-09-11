# THE MODULE'S SHELL | Sourced by Oak in front of everything this module runs
#
# Every task, and every piece of shell module.yaml writes for a list, a
# suggestion or a check, is given this file first - so a function named here is
# called from the yaml by name.
#
# Only what more than one script must agree about belongs in it: which image
# this program belongs to is asked by a hook and written by a task, and two
# answers to that would be a device written from something else than was
# checked. Nothing here prints for a person to read, only to the log.

# ////////////////////////////////////////////////////////////////////////////
# SIMULATION
# ////////////////////////////////////////////////////////////////////////////

# --debug runs without touching the machine. Each task guards itself with
# `simulating && return 0` as its first line, so a unit is only ever skipped as
# a whole, and each test with `debugging && return 0` — a simulated run wrote
# nothing, so there is nothing on the machine for it to read.
#
# The pause is the difference between the two: it holds a step on screen long
# enough to be read instead of flashing past, and a test is not a step anybody
# is watching.

debugging() { [ "$DEBUG" = "true" ]; }

simulating() {
    debugging || return 1
    echo "simulated" # Oak has already logged which step this is
    sleep 1          # keep the step visible in the interface instead of flashing past
}

# ////////////////////////////////////////////////////////////////////////////
# THE IMAGE THIS PROGRAM BELONGS TO
# ////////////////////////////////////////////////////////////////////////////

# Where the program was started, which is where Oak keeps the answers and the
# log. The image lands beside them, so a second run finds it again and a folder
# removed takes all of it with it.
HERE="$(dirname "$MODULE_CONF")"

# Not the newest release but the one this program came out of: a binary from
# last month writing this month's image is two versions on one machine, and
# only one of them was ever tested together. oak.yaml beside the binary is the
# single place that version is written down.
VERSION="$(sed -n 's/^version:[[:space:]]*//p' "${HERE}/oak.yaml")"
TAG="v${VERSION}"

# The release the tag names, asked once and read by everything below. Empty
# when this machine cannot reach GitHub, which is not an error on its own: an
# image already here needs no release at all.
release() {
    curl -Lfs "https://api.github.com/repos/murkl/arch-os/releases/tags/${TAG}" || true
}

# The address of the one asset of that release whose name ends the given way.
# Matched on the ending rather than on the name, so ".iso" is the image and
# never the checksum beside it, and a renamed download stays a change to the
# build and nothing here.
#
# One awk rather than a pipeline of greps: finding nothing is an answer here and
# not a failure - the caller decides what an empty line means - and grep would
# make "no match" the status of the whole function under pipefail.
asset_url() {
    release | awk -v suffix="$1" '
        match($0, /"browser_download_url": *"[^"]*"/) {
            url = substr($0, RSTART, RLENGTH)
            sub(/.*: *"/, "", url)
            sub(/"$/, "", url)
            if (substr(url, length(url) - length(suffix) + 1) == suffix) { print url; exit }
        }'
}

# What the image is called on this machine. Named after the version rather than
# read out of the release, so the hook that checks whether it is already here
# needs no network to answer.
image() { printf '%s/arch-os-%s-x86_64.iso' "$HERE" "$VERSION"; }

# ////////////////////////////////////////////////////////////////////////////
# THE DEVICE
# ////////////////////////////////////////////////////////////////////////////

# The USB disks this machine has: the device path, a tab, and what a person
# picks it by. Nobody knows their stick as /dev/sdb, and the size and the model
# are what one of them is told apart from the next by.
#
# By transport rather than by anything read off the partitions: a disk this
# machine boots from is not on a USB bus, so it cannot turn up in this list at
# all - which is the one mistake here that cannot be taken back.
list_devices() {
    lsblk -dn -o PATH,TRAN,SIZE,MODEL |
        awk '$2 == "usb" { path = $1; $1 = ""; $2 = ""; sub(/^ +/, ""); sub(/ +$/, ""); print path "\t" path "  " $0 }'
}

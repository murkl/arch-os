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
# WHAT THIS MACHINE IS
# ////////////////////////////////////////////////////////////////////////////

# Whether this machine is running from a booted live image, which is the one
# machine this module does not belong on - see `requires:` in module.yaml.
#
# Not "is it Arch", the way the other two ask: a device is written from any
# Linux at all. What is asked here is only whether this machine is the one that
# was booted from such a device, because that is the machine with something else
# to be doing.
on_live_image() {
    [ -d /run/archiso ] || grep -qs archisobasedir /proc/cmdline
}

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

# Where the program was started, which is where Oak keeps the answers, the log
# and the oak.yaml that says which version this is.
HERE="$(dirname "$MODULE_CONF")"

# Not the newest release but the one this program came out of: a binary from
# last month writing this month's image is two versions on one machine, and
# only one of them was ever tested together. oak.yaml beside the binary is the
# single place that version is written down.
VERSION="$(sed -n 's/^version:[[:space:]]*//p' "${HERE}/oak.yaml")"
TAG="v${VERSION}"

# Every request this module makes. https even after a redirect, because -L would
# otherwise follow a 302 into plain http, where the answer can be anybody's -
# and a connect timeout, so a machine behind a black hole says so rather than
# hanging on the page before the first question.
fetch_url() {
    curl -Lf --proto '=https' --proto-redir '=https' --connect-timeout 10 "$@"
}

# The release the tag names, asked once per script: two questions about the same
# release are one request. Empty when this machine cannot reach GitHub, which is
# not an error on its own - an image already here needs no release at all - and
# an unanswered question stays unanswered for that script rather than being
# asked again at every turn.
release() {
    [ -n "${RELEASE_JSON+set}" ] ||
        RELEASE_JSON="$(fetch_url -s --max-time 20 "https://api.github.com/repos/murkl/arch-os/releases/tags/${TAG}" || true)"
    printf '%s\n' "$RELEASE_JSON"
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

# ////////////////////////////////////////////////////////////////////////////
# WHAT IS KEPT, AND WHERE
# ////////////////////////////////////////////////////////////////////////////

# The folder both downloads go in. The answer, and before there is one - the
# preflight check reads it before the first question - the folder the program
# was started in, which is also what that question suggests: `prefill:` in
# module.yaml calls this, so where it defaults to is said in one place.
download_dir() { printf '%s' "${ARCH_OS_DOWNLOAD_DIR:-$HERE}"; }

# What the image is called there. Named after the version rather than read out
# of the release, so the hook that checks whether it is already here needs no
# network to answer.
image() { printf '%s/arch-os-%s-x86_64.iso' "$(download_dir)" "$VERSION"; }

# And the checksum published beside it, which carries the image's own name - so
# `sha256sum -c` in that folder is the check anybody would run by hand.
checksum() { printf '%s.sha256' "$(image)"; }

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
#
# Read again by the task that writes, because the answer outlives the machine's
# view of its own disks: /dev/sdb is a path, not a stick.
list_devices() {
    lsblk -dn -o PATH,TRAN,SIZE,MODEL |
        awk '$2 == "usb" { path = $1; $1 = ""; $2 = ""; sub(/^ +/, ""); sub(/ +$/, ""); print path "\t" path "  " $0 }'
}

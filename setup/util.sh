# General shell helpers with no idea what an Arch OS installation is — no
# ARCH_OS_* variable, no MNT, nothing from data/. Sourced by lib.sh before
# anything context-specific, so those pieces can lean on them.
#
# Anything that reaches into this tree's own state belongs in lib.sh instead.

# ─── Simulation ──────────────────────────────────────────────────────────────

# DEBUG=true runs the whole installer without touching the machine: every wall
# steps aside and every task reports success without doing anything. Each task
# guards itself with `simulating && return 0` as its first line, so a unit can
# only ever be skipped as a whole.
: "${DEBUG:=false}"

simulating() {
    [ "$DEBUG" = "true" ] || return 1
    echo "simulated: ${BASH_SOURCE[1]}"
    sleep 1 # so the unit is visible in the interface rather than flashing past
}

# ─── Network ─────────────────────────────────────────────────────────────────

# Real HTTPS to a host the installation needs anyway, not a ping — a captive
# portal answers pings.
is_online() {
    curl -Lsf --connect-timeout 5 --max-time 15 https://archlinux.org >/dev/null
}

# ─── auto / none ─────────────────────────────────────────────────────────────

# `auto` and `none` are the two words the lists in installer.yaml share, and
# neither ever reaches a task. They are not the same test: auto is a value
# still to be found, none is the value itself — the empty answer said out loud.
is_auto() { [ -z "$1" ] || [ "$1" = "auto" ]; }
not_none() { [ "$1" = "none" ] || printf '%s' "$1"; }

# ─── Disks ───────────────────────────────────────────────────────────────────

# The disks this machine has, as a question offers them: the device path is the
# answer, and what follows the tab is what it is chosen by. Nobody picks between
# /dev/sda and /dev/sdb by name — they pick by size and by what the drive is
# called. Whole disks only: 8 is SCSI and SATA, 259 NVMe, 254 virtual block
# devices.
#
# Named rather than written out twice: an installation and a recovery ask for a
# disk in exactly the same words, and a list that differed between them would be
# two answers to one question.
disk_options() {
    lsblk -d -n -I 8,259,254 -o PATH,SIZE,MODEL |
        awk '{ path = $1; $1 = ""; sub(/^ +/, ""); sub(/ +$/, ""); printf "%s\t%s  %s\n", path, path, $0 }'
}

# part_of names a partition of a disk. Devices whose name ends in a digit —
# nvme0n1, mmcblk0, loop0 — put a p between the disk and the number.
part_of() {
    local sep=""
    [[ "$1" =~ [0-9]$ ]] && sep="p"
    printf '%s%s%s' "$1" "$sep" "$2"
}

# ─── Where a task lives ──────────────────────────────────────────────────────

# The folder of the task that called it, where a unit keeps the files it ships
# with.
where() { dirname "${BASH_SOURCE[1]}"; }

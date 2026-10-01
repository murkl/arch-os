# The snapshots the rollback asks for, newest first: the path, a tab, and the
# number, date and reason out of each one's info.xml. None is an answer: the
# step is skipped.

# Simulated, so the page is worth looking at.
if debugging; then
    printf '@snapshots/2/snapshot\t2   2026-08-30 21:04:17 UTC   after a system update\n'
    printf '@snapshots/1/snapshot\t1   2026-08-29 09:12:40 UTC   first root filesystem\n'
    exit 0
fi

# A field at a time, so a broken file costs a column rather than the list.
label() {
    local info="${BTRFS_TOP}/@snapshots/${1}/info.xml"
    local date="" description=""
    if [ -r "$info" ]; then
        date="$(sed -n '0,/<date>.*<\/date>/s:.*<date>\(.*\)</date>.*:\1:p' "$info")"
        description="$(sed -n '0,/<description>.*<\/description>/s:.*<description>\(.*\)</description>.*:\1:p' "$info")"
    fi
    printf '%s' "$1"
    [ -z "$date" ] || printf '   %s UTC' "$date" # snapper records UTC
    [ -z "$description" ] || printf '   %s' "$description"
    echo
}

# By the number snapper counts up with, not by the order btrfs lists them in.
while read -r path; do
    printf '%s\t%s\n' "$path" "$(label "$(printf '%s' "$path" | cut -d/ -f2)")"
done < <(btrfs subvolume list -o "${BTRFS_TOP}/@snapshots" | awk '{ print $NF }' | sort -t/ -k2 -rn)

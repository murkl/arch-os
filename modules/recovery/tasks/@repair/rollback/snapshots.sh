# The snapshots this run can go back to, newest first: the path a rollback
# reaches one by, then a tab, then what it is chosen by. A number alone is not
# something anyone can pick between, so the date and the reason are read out of
# each snapshot's own info.xml.
#
# Nothing to list is an answer rather than a failure: a system without snapshots
# is one where this step is skipped.

# Simulated, so the page that asks is worth looking at while this module is
# being worked on.
if debugging; then
    printf '@snapshots/2/snapshot\t2   2026-08-30 21:04:17 UTC   after a system update\n'
    printf '@snapshots/1/snapshot\t1   2026-08-29 09:12:40 UTC   first root filesystem\n'
    exit 0
fi

[ -d "${BTRFS_TOP}/@snapshots" ] || exit 0

# One snapshot as it reads in a list. Unreadable info leaves the number standing
# on its own: a snapshot that cannot describe itself is still one to go back to.
label() {
    local info="${BTRFS_TOP}/@snapshots/${1}/info.xml"
    local date="" description=""

    # A field at a time, so a broken file costs a column rather than the list,
    # and only from a file that is there: every script runs under a trap that
    # takes a read that failed for a list that failed. 0,/.../ ends at the first
    # match, so sed hands over one line and still reads to the end.
    if [ -r "$info" ]; then
        date="$(sed -n '0,/<date>.*<\/date>/s:.*<date>\(.*\)</date>.*:\1:p' "$info")"
        description="$(sed -n '0,/<description>.*<\/description>/s:.*<description>\(.*\)</description>.*:\1:p' "$info")"
    fi

    printf '%s' "$1"
    # snapper records the date in UTC, which the list says rather than passing
    # it off as the local time the system itself shows it in.
    [ -z "$date" ] || printf '   %s UTC' "$date"
    [ -z "$description" ] || printf '   %s' "$description"
    echo
}

# Newest first is by the number snapper counts up with, not by the order btrfs
# happens to list them in.
while read -r path; do
    printf '%s\t%s\n' "$path" "$(label "$(printf '%s' "$path" | cut -d/ -f2)")"
done < <(btrfs subvolume list -o "${BTRFS_TOP}/@snapshots" | awk '{ print $NF }' | sort -t/ -k2 -rn)

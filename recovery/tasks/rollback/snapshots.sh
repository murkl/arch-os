# The snapshots this run can go back to, newest first: the path a rollback
# reaches one by, then a tab, then what it is chosen by.
#
# A number alone is not something anyone can pick between, so the date and the
# reason are read out of each snapshot's own info.xml. It is asked by the
# rollback task, in the middle of the run - the disk holding these has only just
# been unlocked.

# Simulated, so the page that asks is worth looking at while this tree is being
# worked on.
if [ "$DEBUG" = "true" ]; then
    printf '@snapshots/2/snapshot\t2   2026-08-30 21:04   after a system update\n'
    printf '@snapshots/1/snapshot\t1   2026-08-29 09:12   first root filesystem\n'
    exit 0
fi

# One snapshot as it reads in a list. Unreadable info leaves the number standing
# on its own: a snapshot that cannot describe itself is still one to go back to.
label() {
    local info="${BTRFS_TOP}/@snapshots/${1}/info.xml"
    local field
    printf '%s' "$1"
    for field in date description; do
        # A line at a time, so a broken file costs a column rather than the
        # whole list.
        sed -n "s:.*<${field}>\(.*\)</${field}>.*:\1:p" "$info" 2>/dev/null |
            head -n1 | sed 's/^/   /' | tr -d '\n'
    done
    echo
}

# Newest first is by the number snapper counts up with, not by the order btrfs
# happens to list them in.
while read -r path; do
    printf '%s\t%s\n' "$path" "$(label "$(printf '%s' "$path" | cut -d/ -f2)")"
done < <(btrfs subvolume list -o "${BTRFS_TOP}/@snapshots" | awk '{ print $NF }' | sort -t/ -k2 -rn)

# Nothing of an earlier attempt is left holding the disk the next task is about
# to partition, and the clock the new system inherits is on network time.

if mountpoint -q "$MNT"; then
    echo "${MNT} is still mounted" >&2
    exit 1
fi
timedatectl show -p NTP --value | grep -qx yes

# Nothing of an earlier attempt is left holding the disk the next task is about
# to partition, and the clock the new system inherits is on network time.
debugging && return 0

! mountpoint -q "$MNT"
timedatectl show -p NTP --value | grep -qx yes

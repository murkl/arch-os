# The system is actually reachable at the mount point everything after this
# writes through.
debugging && return 0

mountpoint -q "$MNT"
[ -f "${MNT}/etc/os-release" ]

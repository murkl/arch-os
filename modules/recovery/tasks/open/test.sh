# The system is actually reachable at the mount point everything after this
# writes through.
mountpoint -q "$MNT"
[ -f "${MNT}/etc/os-release" ]

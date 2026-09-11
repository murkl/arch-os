# The two mount points every later task writes through. Checking them here is
# what turns "the disk was set up" into something read off the machine.
mountpoint -q "$MNT"
mountpoint -q "${MNT}/boot"

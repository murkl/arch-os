# The timer is what does the work; the package it comes in is only what it needs.
debugging && return 0

arch-chroot "$MNT" systemctl is-enabled btrfs-scrub@-.timer >/dev/null

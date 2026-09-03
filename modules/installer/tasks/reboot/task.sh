# Close the new system cleanly and restart into it. A target that will not
# unmount does not hold the restart back: everything is on the disk, and systemd
# flushes whatever is left on the way down.

simulating && return 0

unmount_target || echo "restarting with the target still mounted"
reboot

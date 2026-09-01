# Close the new system cleanly and restart into it.
#
# A target that will not unmount does not hold the restart back: everything is
# on the disk, and systemd unmounts and flushes whatever is left on the way
# down. The installation is over by now, and calling it failed over a mount
# nobody needs any more would say something untrue about what is on the disk.

simulating && return 0

unmount_target || echo "restarting with the target still mounted"
reboot

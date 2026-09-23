# Into the system that was just installed. A target that will not unmount does
# not hold the restart back: everything is on the disk, and systemd flushes
# whatever is left on the way down.

close_target || echo "restarting with the target still mounted"
reboot

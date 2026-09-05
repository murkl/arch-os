# Close whatever the installation had open and restart this machine.
#
# Unmounting first, so a machine restarted halfway through does not take a
# half-written file system with it. Nothing mounted is not an error.

simulating && return 0

close_target || true
systemctl reboot

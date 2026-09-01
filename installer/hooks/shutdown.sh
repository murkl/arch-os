# Close whatever the installation had open and switch this machine off.
#
# Unmounting first, so a machine stopped halfway through does not take a
# half-written file system with it. Nothing mounted is not an error.

simulating && return 0

unmount_target || true
systemctl poweroff

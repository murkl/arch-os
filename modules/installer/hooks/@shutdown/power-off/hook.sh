# Unmounting first, so a machine stopped halfway through does not take a
# half-written file system with it. Nothing mounted is not an error.

simulating && return 0

close_target || true
systemctl poweroff

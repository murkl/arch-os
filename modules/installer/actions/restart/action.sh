# Unmounting first, so a machine restarted halfway through does not take a
# half-written file system with it. Nothing mounted is not an error.

close_target || true
systemctl reboot

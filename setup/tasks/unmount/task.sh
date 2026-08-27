# Close the new system cleanly: swap off, everything unmounted, the encrypted
# volume locked again.

simulating && return 0

unmount_target

# The new system closed cleanly: swap off, everything unmounted, the encrypted
# volume locked again. See close_target in module.sh, which the restart and the
# two ways out share, so none of them can disagree about what closing is.

simulating && return 0

close_target

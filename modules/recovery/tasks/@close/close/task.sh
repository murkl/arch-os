# Everything the recovery mounted, taken back down, and the encrypted volume
# locked again. See close_target in module.sh, which the two ways out share.

simulating && return 0

close_target

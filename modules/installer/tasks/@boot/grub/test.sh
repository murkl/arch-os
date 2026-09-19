# A machine that will not boot is the one failure nothing later makes up for, so
# what is checked is what the firmware reaches for.
simulating && return 0

[ -f "${MNT}/boot/grub/grub.cfg" ]

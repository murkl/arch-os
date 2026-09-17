# A machine that will not boot is the one failure nothing later can make up for,
# so what is checked is what the firmware actually reaches for: the menu GRUB
# was told to generate.
debugging && return 0

[ -f "${MNT}/boot/grub/grub.cfg" ]

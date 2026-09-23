# A machine that will not boot is the one failure nothing later makes up for, so
# what is checked is what the firmware reaches for.

[ -f "${MNT}/boot/grub/grub.cfg" ]

# The drop-in directory is recent, and a drop-in grub-mkconfig never sourced
# leaves a menu that boots with the stock command line instead of this one.
grep -qF -- "$(kernel_args)" "${MNT}/boot/grub/grub.cfg"

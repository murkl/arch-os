# A machine that will not boot is the one failure nothing later makes up for, so
# what is checked is the loader as it reports itself from inside the new system.
debugging && return 0

arch-chroot "$MNT" bootctl --esp-path=/boot is-installed | grep -qx yes

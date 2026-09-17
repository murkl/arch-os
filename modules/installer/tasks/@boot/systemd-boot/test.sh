# A machine that will not boot is the one failure nothing later can make up for,
# so what is checked is what the firmware actually reaches for: the loader, as
# it reports itself from inside the system being installed.
debugging && return 0

arch-chroot "$MNT" bootctl --esp-path=/boot is-installed | grep -qx yes

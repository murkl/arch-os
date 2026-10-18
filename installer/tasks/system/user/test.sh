# passwd prints nothing, so a missing password shows nowhere else.
arch-chroot "$MNT" id -nG "$ARCH_OS_USERNAME" | grep -qw wheel
arch-chroot "$MNT" passwd -S "$ARCH_OS_USERNAME" | awk '{ exit $2 != "P" }'
arch-chroot "$MNT" passwd -S root | awk '{ exit $2 != "L" }'

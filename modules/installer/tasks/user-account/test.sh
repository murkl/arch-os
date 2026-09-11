# The account exists, may sudo, and has a password - the last of which is the
# one thing here nothing else would ever show, since passwd prints nothing.
arch-chroot "$MNT" id -nG "$ARCH_OS_USERNAME" | grep -qw wheel
arch-chroot "$MNT" passwd -S "$ARCH_OS_USERNAME" | awk '{ exit $2 != "P" }'
arch-chroot "$MNT" passwd -S root | awk '{ exit $2 != "P" }'

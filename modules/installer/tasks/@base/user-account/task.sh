# Create the account and set the passwords.

simulating && return 0

arch-chroot "$MNT" useradd -m -G wheel -s /bin/bash "$ARCH_OS_USERNAME"
mkdir -p "${MNT}/home/${ARCH_OS_USERNAME}/.config" "${MNT}/home/${ARCH_OS_USERNAME}/.local/share"
own_home

# A drop-in rather than an edit of /etc/sudoers: that file belongs to the sudo
# package, and a syntax error in it locks the account out of root entirely.
sudoers_rule 10-wheel '%wheel ALL=(ALL:ALL) ALL'

# Both passwords on stdin, the same one twice because that is what passwd reads.
# It never reaches an argument list, a file or the log.
printf '%s\n%s' "$ARCH_OS_PASSWORD" "$ARCH_OS_PASSWORD" | arch-chroot "$MNT" passwd
printf '%s\n%s' "$ARCH_OS_PASSWORD" "$ARCH_OS_PASSWORD" | arch-chroot "$MNT" passwd "$ARCH_OS_USERNAME"

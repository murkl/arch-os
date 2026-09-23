# Create the account and set the passwords.

simulating && return 0

arch-chroot "$MNT" useradd -m -G wheel -s /bin/bash "$ARCH_OS_USERNAME"
mkdir -p "${MNT}/home/${ARCH_OS_USERNAME}/.config" "${MNT}/home/${ARCH_OS_USERNAME}/.local/share"
own_home

render "$(where)/10-wheel" | sudoers_rule 10-wheel

# On stdin, the same one twice because that is what passwd reads. It never
# reaches an argument list, a file or the log.
printf '%s\n%s' "$ARCH_OS_PASSWORD" "$ARCH_OS_PASSWORD" | arch-chroot "$MNT" passwd
printf '%s\n%s' "$ARCH_OS_PASSWORD" "$ARCH_OS_PASSWORD" | arch-chroot "$MNT" passwd "$ARCH_OS_USERNAME"

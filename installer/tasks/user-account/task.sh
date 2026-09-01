# Create the account and set the passwords.

simulating && return 0

arch-chroot "$MNT" useradd -m -G wheel -s /bin/bash "$ARCH_OS_USERNAME"
mkdir -p "${MNT}/home/${ARCH_OS_USERNAME}/.config" "${MNT}/home/${ARCH_OS_USERNAME}/.local/share"
arch-chroot "$MNT" chown -R "${ARCH_OS_USERNAME}:${ARCH_OS_USERNAME}" "/home/${ARCH_OS_USERNAME}"

sed -i 's^# %wheel ALL=(ALL:ALL) ALL^%wheel ALL=(ALL:ALL) ALL^g' "${MNT}/etc/sudoers"

# Both passwords on stdin, the same one twice because that is what passwd reads.
# It never reaches an argument list, a file or the log.
printf '%s\n%s' "$ARCH_OS_PASSWORD" "$ARCH_OS_PASSWORD" | arch-chroot "$MNT" passwd
printf '%s\n%s' "$ARCH_OS_PASSWORD" "$ARCH_OS_PASSWORD" | arch-chroot "$MNT" passwd "$ARCH_OS_USERNAME"

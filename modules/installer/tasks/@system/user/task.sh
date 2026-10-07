arch-chroot "$MNT" useradd -m -G wheel -s /bin/bash "$ARCH_OS_USERNAME"
mkdir -p "${MNT}/home/${ARCH_OS_USERNAME}/.config" "${MNT}/home/${ARCH_OS_USERNAME}/.local/share"
own_home

render "$(where)/10-wheel" | sudoers_rule 10-wheel

# On stdin, twice because passwd asks twice; never in an argument or the log.
# Root keeps the locked password Arch ships: docs/REFERENCE.md#accounts
printf '%s\n%s' "$ARCH_OS_PASSWORD" "$ARCH_OS_PASSWORD" | arch-chroot "$MNT" passwd "$ARCH_OS_USERNAME"

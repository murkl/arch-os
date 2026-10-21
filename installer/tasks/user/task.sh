arch-chroot "$MNT" useradd -m -G wheel -s /bin/bash "$ARCH_OS_USERNAME"
mkdir -p "$(user_home)/.config" "$(user_home)/.local/share"
own_home

render "$(where)/10-wheel" | sudoers_rule 10-wheel

# On stdin, as chpasswd takes it, never in an argument or the log. Root keeps
# the locked password Arch ships: docs/REFERENCE.md#accounts
printf '%s:%s\n' "$ARCH_OS_USERNAME" "$ARCH_OS_PASSWORD" | arch-chroot "$MNT" chpasswd

run arch-chroot "$MNT" useradd -m -G wheel -s /bin/bash "$ARCH_OS_USERNAME"
run mkdir -p "$(user_home)/.config" "$(user_home)/.local/share"
own_home

render "$(where)/10-wheel" | sudoers_rule 10-wheel

# On stdin, never in an argument or the log, and in the script by its variable.
# Root stays locked, as Arch ships it: docs/REFERENCE.md#accounts
run_sh "printf '%s:%s\\n' $(shell_line "$ARCH_OS_USERNAME") \"\$ARCH_OS_PASSWORD\" | $(shell_line arch-chroot "$MNT" chpasswd)"

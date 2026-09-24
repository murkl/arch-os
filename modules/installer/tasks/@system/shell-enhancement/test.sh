# zsh is the shell that opens for the account, and root keeps bash.

home="${MNT}/home/${ARCH_OS_USERNAME}"

arch-chroot "$MNT" getent passwd "$ARCH_OS_USERNAME" | grep -q ':/usr/bin/zsh$'
arch-chroot "$MNT" getent passwd root | grep -q ':/usr/bin/bash$'

# Every rendered file, read by the shell that reads it: a file that does not
# parse is a login that says so on every terminal the machine opens.
for file in "${MNT}/root/.bashrc" "${MNT}/root/.aliases" "${home}/.bashrc" "${home}/.aliases"; do
    bash -n "$file"
done
arch-chroot "$MNT" zsh -n "/home/${ARCH_OS_USERNAME}/.zshrc"

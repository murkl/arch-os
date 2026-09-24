# zsh is the shell that opens, for root and for the account.

home="${MNT}/home/${ARCH_OS_USERNAME}"

for account in root "$ARCH_OS_USERNAME"; do
    arch-chroot "$MNT" getent passwd "$account" | grep -q ':/usr/bin/zsh$'
done

# Every rendered file, read by the shell that reads it: a file that does not
# parse is a login that says so on every terminal the machine opens.
for file in "${MNT}/root/.bashrc" "${MNT}/root/.aliases" "${home}/.bashrc" "${home}/.aliases"; do
    bash -n "$file"
done
for file in /root/.zshrc "/home/${ARCH_OS_USERNAME}/.zshrc"; do
    arch-chroot "$MNT" zsh -n "$file"
done

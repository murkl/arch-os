home="${MNT}/home/${ARCH_OS_USERNAME}"

arch-chroot "$MNT" getent passwd "$ARCH_OS_USERNAME" | grep -q ':/usr/bin/zsh$'
arch-chroot "$MNT" getent passwd root | grep -q ':/usr/bin/bash$'

# Each file parsed by its shell: one that does not is an error on every terminal.
for file in "${MNT}/root/.bashrc" "${MNT}/root/.aliases" "${home}/.bashrc" "${home}/.aliases"; do
    bash -n "$file"
done
arch-chroot "$MNT" zsh -n "/home/${ARCH_OS_USERNAME}/.zshrc"

home="$(user_home)"

arch-chroot "$MNT" getent passwd "$ARCH_OS_USERNAME" | grep -q ':/usr/bin/zsh$'
arch-chroot "$MNT" getent passwd root | grep -q ':/usr/bin/bash$'

# A syntax error shows in every terminal.
for file in "${MNT}/root/.bashrc" "${MNT}/root/.aliases" "${home}/.bashrc" "${home}/.aliases"; do
    bash -n "$file"
done
arch-chroot "$MNT" zsh -n "/home/${ARCH_OS_USERNAME}/.zshrc"

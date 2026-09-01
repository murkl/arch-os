# Packages pulled in as dependencies of something that has since gone.

simulating && return 0

# shellcheck disable=SC2016  # the subshell has to run inside the chroot, not here
arch-chroot "$MNT" bash -c 'pacman -Qtdq >/dev/null 2>&1 && pacman -Rns --noconfirm $(pacman -Qtdq) || true'

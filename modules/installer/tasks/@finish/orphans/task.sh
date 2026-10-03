# What came as a dependency of something since removed. Late, because what is
# an orphan depends on everything installed before.
# shellcheck disable=SC2016  # expanded inside the chroot
arch-chroot "$MNT" bash -c 'pacman -Qtdq >/dev/null 2>&1 && pacman -Rns --noconfirm $(pacman -Qtdq) || true'

# Packages that arrived as a dependency of something that has since gone. Last,
# because what is an orphan depends on everything installed before it.

# shellcheck disable=SC2016  # pacman inside the chroot expands this, not us
arch-chroot "$MNT" bash -c 'pacman -Qtdq >/dev/null 2>&1 && pacman -Rns --noconfirm $(pacman -Qtdq) || true'

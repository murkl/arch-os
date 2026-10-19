# What came as a dependency of something since removed. Late, because what is
# an orphan depends on everything installed before. pacman answers none with
# status 1, so the list decides.
list="$(arch-chroot "$MNT" pacman -Qtdq || allow 1)"
if [ -z "$list" ]; then
    echo "no orphaned packages"
    return 0
fi
mapfile -t orphans <<<"$list"
arch-chroot "$MNT" pacman -Rns --noconfirm "${orphans[@]}"

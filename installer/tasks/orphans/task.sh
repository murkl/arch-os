# Late, since what is an orphan depends on everything installed before. pacman
# exits 1 for none, so the list decides.
list="$(arch-chroot "$MNT" pacman -Qtdq || allow 1)"
if [ -z "$list" ]; then
    echo "no orphaned packages"
    return 0
fi
mapfile -t orphans <<<"$list"
arch-chroot "$MNT" pacman -Rns --noconfirm "${orphans[@]}"

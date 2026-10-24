# pacman exits 1 for none and for an error alike, so the list decides.
orphans="$(arch-chroot "$MNT" pacman -Qtdq || true)"
if [ -n "$orphans" ]; then
    echo "still orphaned: $(tr '\n' ' ' <<<"$orphans")" >&2
    exit 1
fi

# pacman says "none" and "could not read" with one exit status, so the list is
# what is judged.
orphans="$(arch-chroot "$MNT" pacman -Qtdq || true)"
if [ -n "$orphans" ]; then
    echo "still orphaned: $(tr '\n' ' ' <<<"$orphans")" >&2
    exit 1
fi

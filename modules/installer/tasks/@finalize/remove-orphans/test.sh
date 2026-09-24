# Nothing is left that nothing asked for: a removal that half worked leaves
# exactly this list. pacman says "none" and "could not read" with the same exit
# status, so the list itself is what is judged.

orphans="$(arch-chroot "$MNT" pacman -Qtdq || true)"
if [ -n "$orphans" ]; then
    echo "still orphaned: $(tr '\n' ' ' <<<"$orphans")" >&2
    exit 1
fi

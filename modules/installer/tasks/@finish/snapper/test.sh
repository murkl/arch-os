arch-chroot "$MNT" test -d /.snapshots

# Read back out of snapper itself: set-config accepts a mangled value without a
# word, and the limits it then keeps are the package's.
config="$(arch-chroot "$MNT" snapper --no-dbus --csvout --no-headers -c root get-config)"
while IFS= read -r setting; do
    grep -qxF "${setting/=/,}" <<<"$config"
done <"$(where)/settings"

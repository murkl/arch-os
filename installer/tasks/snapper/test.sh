arch-chroot "$MNT" test -d /.snapshots
arch-chroot "$MNT" systemctl is-enabled snapper-cleanup.timer >/dev/null
if arch-chroot "$MNT" systemctl is-enabled -q snapper-timeline.timer; then
    echo "snapper-timeline.timer is on, with no timeline to take" >&2
    exit 1
fi

# Read back out of snapper itself: set-config accepts a mangled value without a
# word, and the limits it then keeps are the package's.
config="$(arch-chroot "$MNT" snapper --no-dbus --csvout --no-headers -c root get-config)"
while IFS= read -r setting; do
    grep -qxF "${setting/=/,}" <<<"$config"
done <"$(where)/settings"

# The account reaches no snapshot, neither through the folder nor through snapper.
if as_user "ls /.snapshots" >/dev/null 2>&1; then
    echo "the account can read /.snapshots" >&2
    exit 1
fi
grep -qxF 'ALLOW_GROUPS,' <<<"$config"

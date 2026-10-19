# Every link opens in the browser chosen, as GLib, which GNOME asks, says.
entry="$(browser_entry)"
arch-chroot "$MNT" test -f "/usr/share/applications/${entry}"
while read -r type; do
    answer="$(as_user "gio mime ${type}")"
    grep -qF ": ${entry}" <<<"$answer"
done <"$(where)/types"

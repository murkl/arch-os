# Every link opens in the browser that was chosen: its entry is one the package
# installed, and GLib, which GNOME asks, names it as the default.

entry="$(browser_entry)"
arch-chroot "$MNT" test -f "/usr/share/applications/${entry}"

while read -r type; do
    answer="$(as_user "gio mime ${type}")"
    grep -qF ": ${entry}" <<<"$answer"
done < <(browser_types)

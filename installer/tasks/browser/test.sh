# Through GLib, which GNOME asks.
entry="$(browser_entry)"
arch-chroot "$MNT" test -f "/usr/share/applications/${entry}"
while read -r type; do
    answer="$(as_user "gio mime ${type}")"
    grep -qF ": ${entry}" <<<"$answer"
done <"$(where)/types"

# GNOME Web decodes through GStreamer, on the GPU with its va plugin.
[ "$ARCH_OS_BROWSER" != epiphany ] || [ -f "${MNT}/usr/lib/gstreamer-1.0/libgstva.so" ]

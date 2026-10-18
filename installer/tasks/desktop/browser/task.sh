# The browser chosen, in this system's language, and the one every link opens
# in. Each already runs on Wayland, decodes video on the card and keeps its
# passwords in the GNOME keyring; only what it does not bring is added.
# https://wiki.archlinux.org/title/Firefox
# https://wiki.archlinux.org/title/Chromium
# https://wiki.archlinux.org/title/Vivaldi

locale="${ARCH_OS_LOCALE_LANG%%.*}"
language="${locale%%_*}"
territory=""
[[ $locale == *_* ]] && territory="${locale#*_}"
territory="${territory,,}"

packages=("$ARCH_OS_BROWSER")

# The first of these the repositories hold. None is said in the log and the
# browser stays in English; a pacman that cannot answer stops the run.
add_first_of() {
    local name out
    for name in "$@"; do
        if out="$(arch-chroot "$MNT" env LC_ALL=C pacman -Sp --print-format %n "$name" 2>&1)"; then
            packages+=("$name")
            return 0
        fi
        if [[ $out != *"target not found"* ]]; then
            echo "$out" >&2
            return 1
        fi
    done
    echo "none of $* is in the repositories, ${locale} goes without it"
}

add_dictionary() {
    add_first_of "hunspell-${language}_${territory}" "hunspell-${language}" "hunspell-${language}_any"
}

case "$ARCH_OS_BROWSER" in
epiphany)
    # WebKit plays media through GStreamer and checks spelling through enchant.
    packages+=(gst-plugins-good gst-plugins-bad gst-libav hunspell)
    add_dictionary
    ;;
firefox)
    # Arch's build follows the system language and dictionaries by itself.
    add_first_of "firefox-i18n-${language}-${territory}" "firefox-i18n-${language}"
    add_dictionary
    ;;
vivaldi)
    # The codecs from the repositories, not a download into the home.
    packages+=(vivaldi-ffmpeg-codecs)
    ;;
esac

chroot_pacman_install "${packages[@]}"

# Written where GNOME reads it, by GLib's own tool.
while read -r type; do
    as_user "gio mime ${type} $(browser_entry)"
done <"$(where)/types"

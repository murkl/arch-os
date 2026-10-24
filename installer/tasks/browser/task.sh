# Each browser already runs on Wayland, decodes video on the GPU and keeps its
# passwords in the GNOME keyring. Only what it lacks is added.
# https://wiki.archlinux.org/title/Firefox
# https://wiki.archlinux.org/title/Chromium
# https://wiki.archlinux.org/title/Vivaldi

locale="${ARCH_OS_LOCALE_LANG%%.*}"
language="${locale%%_*}"
territory=""
[[ $locale == *_* ]] && territory="${locale#*_}"
territory="${territory,,}"

packages=("$ARCH_OS_BROWSER")

# Adds the first package the repositories hold. None is logged, any other
# pacman error fails.
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
    echo "none of $* is in the repositories for ${locale}"
}

add_dictionary() {
    add_first_of "hunspell-${language}_${territory}" "hunspell-${language}" "hunspell-${language}_any"
}

case "$ARCH_OS_BROWSER" in
epiphany)
    # WebKit plays media through GStreamer and checks spelling through enchant
    # with hunspell.
    packages+=(gst-plugins-good gst-plugins-bad gst-libav hunspell)
    add_dictionary
    ;;
firefox)
    # Arch's build picks up the language pack and the dictionaries by itself.
    add_first_of "firefox-i18n-${language}-${territory}" "firefox-i18n-${language}"
    add_dictionary
    ;;
vivaldi)
    # Codecs from the repositories instead of a download into the home.
    packages+=(vivaldi-ffmpeg-codecs)
    ;;
esac

chroot_pacman_install "${packages[@]}"

# GLib's own tool, so GNOME reads the association.
while read -r type; do
    as_user "gio mime ${type} $(browser_entry)"
done <"$(where)/types"

# The browser chosen, in the language this system is set up in, and the one
# every link opens in. Only what a browser does not bring itself is added here:
# on this desktop each of them already runs on Wayland, decodes video on the
# card where the driver can - Chromium's own since 140 and 143, with no flag -
# and keeps its passwords in the keyring GNOME unlocks at login.
# https://wiki.archlinux.org/title/Firefox
# https://wiki.archlinux.org/title/Chromium
# https://wiki.archlinux.org/title/Vivaldi

locale="${ARCH_OS_LOCALE_LANG%%.*}"
language="${locale%%_*}"
territory=""
[[ $locale == *_* ]] && territory="${locale#*_}"
territory="${territory,,}"

packages=("$ARCH_OS_BROWSER")

# The first of these names the repositories hold a package for. A language pack
# or a dictionary exists for many languages but not for every one, so finding
# none is said in the log and the browser stays in English there. A name another
# package provides counts, so hunspell-fr finds one of French's three spellings.
# Not found is told apart from a pacman that could not answer at all, which
# stops the run instead.
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

# Spelling checked in the system's language, by both browsers that read
# hunspell's dictionaries rather than fetching their own.
add_dictionary() {
    add_first_of "hunspell-${language}_${territory}" "hunspell-${language}" "hunspell-${language}_any"
}

case "$ARCH_OS_BROWSER" in
epiphany)
    # WebKit plays media through GStreamer, which decodes nothing without its
    # plugins, and checks spelling through enchant, which reaches the
    # dictionaries only with hunspell beside it. The desktop extras bring the
    # same plugins; a browser has to play a video without them.
    packages+=(gst-plugins-good gst-plugins-bad gst-libav hunspell)
    add_dictionary
    ;;
firefox)
    # Arch's Firefox is set to follow the system language and to read the
    # system's dictionaries (vendor.js in its PKGBUILD), and never asks to be
    # the default. Both only have to be there.
    add_first_of "firefox-i18n-${language}-${territory}" "firefox-i18n-${language}"
    add_dictionary
    ;;
vivaldi)
    # The codecs for H.264 and AAC from the repositories, rather than the
    # library Vivaldi otherwise downloads into the home on its first start.
    packages+=(vivaldi-ffmpeg-codecs)
    ;;
esac

# Chromium follows the system language and fetches its own dictionaries, so it
# needs nothing beside its package.
chroot_pacman_install "${packages[@]}"

# Written where GNOME reads it, by GLib's own tool.
while read -r type; do
    as_user "gio mime ${type} $(browser_entry)"
done < <(browser_types)

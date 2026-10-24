arch-chroot "$MNT" systemctl is-enabled gdm.service >/dev/null

# A boot counts as good only once a graphical session is up.
arch-chroot "$MNT" systemctl is-enabled arch-os-session-up.service >/dev/null
[ -z "$(unit_complaints arch-os-session-up.service)" ]

# systemd-oomd acts only on what the drop-ins mark, and systemd skips an
# unreadable key with only a warning, which verify prints.
arch-chroot "$MNT" systemctl is-enabled systemd-oomd.service >/dev/null
[ -z "$(unit_complaints -.slice user@.service)" ]

if [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
    arch-chroot "$MNT" systemctl is-enabled power-profiles-daemon.service >/dev/null
    arch-chroot "$MNT" systemctl is-enabled cups.socket >/dev/null
fi

# Without the timer the firmware metadata goes stale.
if has_command fwupdmgr; then
    arch-chroot "$MNT" systemctl is-enabled fwupd-refresh.timer >/dev/null
fi

has_command gnome-extensions-app

# gnome-shell starts its calendar server at every login and calendar view, and
# a missing library fails each start.
libraries="$(arch-chroot "$MNT" ldd /usr/lib/gnome-shell-calendar-server)"
if grep -F 'not found' <<<"$libraries"; then
    echo "gnome-shell-calendar-server lacks the libraries above" >&2
    exit 1
fi

# Bazaar replaces GNOME Software, and GNOME Firmware its firmware updates.
if [ "$ARCH_OS_FLATPAK_ENABLED" = "true" ] && [ "$ARCH_OS_BAZAAR_ENABLED" = "true" ]; then
    has_command bazaar
    has_command gnome-firmware
    if has_command gnome-software; then
        echo "Bazaar on, but GNOME Software installed" >&2
        exit 1
    fi
else
    has_command gnome-software
fi

arch-chroot "$MNT" systemctl --global is-enabled pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null

# rtkit starts through D-Bus activation and has no service to enable.
[ -f "${MNT}/usr/share/dbus-1/system-services/org.freedesktop.RealtimeKit1.service" ]

# Without nss-mdns avahi runs, but no .local name resolves.
grep -q 'mdns_minimal' "${MNT}/etc/nsswitch.conf"
[ "$ARCH_OS_FIREWALL_ENABLED" != "true" ] ||
    arch-chroot "$MNT" firewall-offline-cmd --zone=public --query-service=mdns >/dev/null

# Automatic login exactly where the LUKS passphrase is the account's password:
# docs/REFERENCE.md#accounts
autologin=false
grep -qs '^AutomaticLoginEnable=True' "${MNT}/etc/gdm/custom.conf" && autologin=true
if [ "$autologin" = "true" ] && [ "$ARCH_OS_ENCRYPTION_ENABLED" != "true" ]; then
    echo "the disk is not encrypted and the login is automatic" >&2
    exit 1
fi
if [ "$autologin" = "true" ] && [ "$ARCH_OS_DISK_PASSWORD_ENABLED" = "true" ]; then
    echo "the disk has a password of its own and the login is automatic" >&2
    exit 1
fi
if [ "$autologin" = "false" ] && [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && [ "$ARCH_OS_DISK_PASSWORD_ENABLED" != "true" ]; then
    echo "one password unlocks the disk and the login is not automatic" >&2
    exit 1
fi

# Flatpak off means none: a group member that depends on it pulls it in with
# Flathub.
if [ "$ARCH_OS_FLATPAK_ENABLED" != "true" ] && has_command flatpak; then
    echo "Flatpak off, but flatpak installed" >&2
    exit 1
fi

# GNOME Boxes runs its machines as the account, so /dev/kvm is open to every
# account, and its packages must not pull jack2.
grep -qsE '^KERNEL=="kvm".*MODE="0666"' "$MNT"/usr/lib/udev/rules.d/*.rules
boxes="$(arch-chroot "$MNT" pacman -Sp --noconfirm gnome-boxes)"
if grep -q '/jack2-' <<<"$boxes"; then
    echo "installing GNOME Boxes would bring jack2 beside PipeWire's JACK" >&2
    exit 1
fi

# Read back through the profile as the account: dconf silently drops an unknown
# key and an invalid value.
gsettings_as_user() { as_user "gsettings $1"; }
schemas="$(gsettings_as_user "list-schemas --print-paths")"
group=""
while IFS= read -r line; do
    case "$line" in
    '' | \#*) continue ;;
    \[*\])
        group="${line:1:-1}"
        continue
        ;;
    esac
    key="${line%%=*}"
    schema=""
    while read -r candidate; do
        grep -qxF "$key" <<<"$(gsettings_as_user "list-keys ${candidate}")" && schema="$candidate"
    done < <(awk -v path="/${group}/" '$2 == path { print $1 }' <<<"$schemas")
    if [ -z "$schema" ]; then
        echo "no schema at /${group}/ has the key ${key}" >&2
        exit 1
    fi
    got="$(gsettings_as_user "get ${schema} ${key}")"
    if [ "$got" != "${line#*=}" ]; then
        echo "${schema} ${key} reads ${got}, not ${line#*=}" >&2
        exit 1
    fi
done < <(cat "${MNT}"/etc/dconf/db/local.d/*)

# Through GLib's lookup, which must find the package's own entry masked.
for entry in "${MNT}"/usr/local/share/applications/*.desktop; do
    grep -qx 'Hidden=true' "$entry" || continue
    name="$(basename "$entry")"
    [ -f "${MNT}/usr/share/applications/${name}" ] || continue
    found="$(as_user "gjs -c \"print(imports.gi.GioUnix.DesktopAppInfo.new('${name}') !== null)\"")"
    if [ "$found" != false ]; then
        echo "${name} is still listed among the applications" >&2
        exit 1
    fi
done

arch-chroot "$MNT" systemctl is-enabled gdm.service >/dev/null

# The start waits for the session in front before it counts as one that worked.
arch-chroot "$MNT" systemctl is-enabled arch-os-session-up.service >/dev/null
[ -z "$(systemd-analyze verify --root="$MNT" arch-os-session-up.service 2>&1)" ]

# systemd-oomd only acts on what its drop-ins mark, and systemd skips a key it
# cannot read with a warning: verify prints it.
arch-chroot "$MNT" systemctl is-enabled systemd-oomd.service >/dev/null
[ -z "$(systemd-analyze verify --root="$MNT" -- -.slice user@.service 2>&1)" ]

# The firmware offered is as current as the catalogue its timer loads.
if has_command fwupdmgr; then
    arch-chroot "$MNT" systemctl is-enabled fwupd-refresh.timer >/dev/null
fi

has_command gnome-extensions-app

# Bazaar takes GNOME Software's place, GNOME Firmware its firmware updates.
if [ "$ARCH_OS_FLATPAK_ENABLED" = "true" ] && [ "$ARCH_OS_BAZAAR_ENABLED" = "true" ]; then
    has_command bazaar
    has_command gnome-firmware
    if has_command gnome-software; then
        echo "Bazaar is on and GNOME Software was installed all the same" >&2
        exit 1
    fi
else
    has_command gnome-software
fi

arch-chroot "$MNT" systemctl --global is-enabled pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null

# Without the module the daemon runs and nothing reaches a .local name.
grep -q 'mdns_minimal' "${MNT}/etc/nsswitch.conf"
[ "$ARCH_OS_FIREWALL_ENABLED" != "true" ] ||
    arch-chroot "$MNT" firewall-offline-cmd --zone=public --query-service=mdns >/dev/null

# Automatic login exactly where the boot password stands in front and is the
# account's too: docs/REFERENCE.md#accounts
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

# Flatpak off means none at all: a member of the group that depends on it would
# bring it and Flathub along.
if [ "$ARCH_OS_FLATPAK_ENABLED" != "true" ] && has_command flatpak; then
    echo "Flatpak is off and flatpak was installed all the same" >&2
    exit 1
fi

# GNOME Boxes works once installed, as it runs its machines as the account:
# KVM is open to every account, and its packages bring no second JACK.
grep -qsE '^KERNEL=="kvm".*MODE="0666"' "$MNT"/usr/lib/udev/rules.d/*.rules
boxes="$(arch-chroot "$MNT" pacman -Sp --noconfirm gnome-boxes)"
if grep -q '/jack2-' <<<"$boxes"; then
    echo "installing GNOME Boxes would bring jack2 beside PipeWire's JACK" >&2
    exit 1
fi

# Every default read back as an account reads it, through the profile: a key no
# schema knows and a value it refuses are dropped without a word. The live
# system's runtime directory is root's, so dconf is left to find its own.
gsettings_as_user() { as_user "env -u XDG_RUNTIME_DIR gsettings $1"; }
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

# Hidden from every account as GLib looks applications up: the package's own
# entry is masked, not only written beside it.
for entry in "${MNT}"/usr/local/share/applications/*.desktop; do
    grep -qx 'Hidden=true' "$entry" || continue
    name="$(basename "$entry")"
    [ -f "${MNT}/usr/share/applications/${name}" ] || continue
    found="$(as_user "env -u XDG_RUNTIME_DIR gjs -c \"print(imports.gi.GioUnix.DesktopAppInfo.new('${name}') !== null)\"")"
    if [ "$found" != false ]; then
        echo "${name} is still listed among the applications" >&2
        exit 1
    fi
done

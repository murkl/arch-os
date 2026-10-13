arch-chroot "$MNT" systemctl is-enabled gdm.service >/dev/null

# The start waits for the session in front before it counts as one that worked.
arch-chroot "$MNT" systemctl is-enabled arch-os-session-up.service >/dev/null
[ -z "$(systemd-analyze verify --root="$MNT" arch-os-session-up.service 2>&1)" ]

has_command gnome-software
has_command gnome-extensions-app

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

# The GNOME desktop: packages, login screen, keyboard, services, and the
# defaults every account starts with.

data="$(where)"

# ─── Packages ──────────────────────────────────────────────────────────────
#
# One transaction: packages that replace each other (pipewire-jack and jack2)
# resolve only when pacman sees them together.

# Named outright, since services are switched on for them below.
# https://wiki.archlinux.org/title/PipeWire#Installation
packages=(git bluez bluez-utils avahi nss-mdns pipewire pipewire-pulse wireplumber)

# PipeWire's JACK, so a JACK program installed later finds one instead of
# asking for jack2: GNOME Boxes is one, by way of qemu-desktop.
packages+=(pipewire-jack)

# Bazaar only beside Flatpak, which it is built on: the question's own
# conditions.
bazaar=false
[ "$ARCH_OS_FLATPAK_ENABLED" = "true" ] && [ "$ARCH_OS_BAZAAR_ENABLED" = "true" ] && bazaar=true

# The group filtered before the download rather than trimmed after it.
mapfile -t desktop < <(arch-chroot "$MNT" pacman -Sgq gnome)
[ "${#desktop[@]}" -gt 0 ] || {
    echo "the gnome package group is empty" >&2
    exit 1
}
left_out=()
while read -r scope name; do
    case "$scope" in '' | \#*) continue ;; esac
    case "$scope" in
    slim) [ "$ARCH_OS_DESKTOP_SLIM_ENABLED" = "true" ] || continue ;;
    no-flatpak) [ "$ARCH_OS_FLATPAK_ENABLED" != "true" ] || continue ;;
    bazaar) [ "$bazaar" = "true" ] || continue ;;
    esac
    left_out+=("$name")
done <"${data}/left-out"
mapfile -t desktop < <(printf '%s\n' "${desktop[@]}" | grep -vxF -f <(printf '%s\n' "${left_out[@]}"))
# GNOME Software comes with it. No PackageKit: Arch builds Software without it
# and pacman stays the one thing that changes the system.
# https://wiki.archlinux.org/title/Pacman/Tips_and_tricks#Graphical
packages+=("${desktop[@]}")

# Bazaar in its place installs Flatpaks only, so the firmware updates Software
# offers come from GNOME Firmware.
[ "$bazaar" = "true" ] && packages+=(bazaar gnome-firmware)

# The Extensions app, a package outside the group since GNOME 51.
packages+=(gnome-extensions-app)

if [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
    # https://wiki.archlinux.org/title/GNOME#Extensions
    packages+=(gnome-browser-connector gnome-themes-extra tuned-ppd cups)

    # Portals for flatpaks and screen sharing; GTK's covers what GNOME's lacks.
    packages+=(xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk)

    # The older audio APIs, laptop codec firmware, and rtkit for pipewire's
    # realtime priority, without which it complains at every login.
    packages+=(pipewire-alsa sof-firmware rtkit)
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-pipewire lib32-pipewire-jack)

    # NetworkManager speaks WireGuard itself; OpenVPN needs the plug-in.
    packages+=(rsync networkmanager-openvpn)

    # Building from the AUR, firmware updates, and opening any drive or archive.
    packages+=(base-devel fwupd bash-completion inetutils
        dosfstools ntfs-3g exfatprogs btrfs-progs nfs-utils
        7zip zip unzip unrar wget jq zenity)

    # https://wiki.archlinux.org/title/Codecs_and_containers
    packages+=(ffmpeg ffmpegthumbnailer gstreamer gst-libav gst-plugin-pipewire
        gst-plugins-good gst-plugins-bad gst-plugins-ugly libdvdcss webp-pixbuf-loader)

    packages+=(gamemode)
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-gamemode)

    # Every script the web has, emoji, two metric-compatible families and the
    # terminal font.
    packages+=(noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-liberation ttf-dejavu
        ttf-firacode-nerd)

    packages+=(adw-gtk-theme)
fi

chroot_pacman_install "${packages[@]}"

# Only gamemode: logind hands sound, video and input to whoever sits at the
# seat, and the old groups now do harm.
# https://wiki.archlinux.org/title/Users_and_groups#Pre-systemd_groups
[ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ] && arch-chroot "$MNT" gpasswd -a "$ARCH_OS_USERNAME" gamemode

# ─── Name resolution ───────────────────────────────────────────────────────
#
# Printers, shares and other machines answer to <name>.local. An edit: glibc
# reads only this file. https://wiki.archlinux.org/title/Avahi#Hostname_resolution
nsswitch="${MNT}/etc/nsswitch.conf"
if ! grep -q 'mdns_minimal' "$nsswitch"; then
    sed -i '/^hosts:/ s/\bresolve\b/mdns_minimal [NOTFOUND=return] resolve/' "$nsswitch"
    grep -q 'mdns_minimal' "$nsswitch" ||
        echo "the hosts line in /etc/nsswitch.conf is not the one this Arch ships, .local names will not resolve" >&2
fi

# ─── Login screen ──────────────────────────────────────────────────────────
#
# Automatic login behind an encrypted disk with one password only, where the
# boot password stands in front; pam_gdm hands the LUKS passphrase on to the
# keyring. Written only then: the file belongs to gdm.
# https://wiki.archlinux.org/title/GNOME/Keyring#PAM_step
if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && [ "$ARCH_OS_DISK_PASSWORD_ENABLED" != "true" ]; then
    mkdir -p "${MNT}/etc/gdm"
    render "${data}/custom.conf" USERNAME="$ARCH_OS_USERNAME" >"${MNT}/etc/gdm/custom.conf"
fi

# ─── Every account's environment ───────────────────────────────────────────

mkdir -p "${MNT}/etc/environment.d"
render "${data}/10-arch-os.conf" >"${MNT}/etc/environment.d/10-arch-os.conf"

# Git passwords in the keyring rather than in a file.
arch-chroot "$MNT" git config --system credential.helper /usr/lib/git-core/git-credential-libsecret

# ─── Keyboard ──────────────────────────────────────────────────────────────
#
# The login screen reads this file through localed, the session its setting;
# both say the same. https://wiki.archlinux.org/title/Xorg/Keyboard_configuration
layout="$(desktop_layout)"
variant="$(not_none "$ARCH_OS_DESKTOP_KEYBOARD_VARIANT")"
mkdir -p "${MNT}/etc/X11/xorg.conf.d"
render "${data}/00-keyboard.conf" \
    LAYOUT="$layout" \
    MODEL="$ARCH_OS_DESKTOP_KEYBOARD_MODEL" \
    VARIANT="$variant" \
    >"${MNT}/etc/X11/xorg.conf.d/00-keyboard.conf"

# ─── Services ──────────────────────────────────────────────────────────────

arch-chroot "$MNT" systemctl enable gdm.service

# A start counts as one that worked once the login screen or the session it
# logs into is up: a desktop that never comes up sends the next starts to the
# fallback, then the Recovery. docs/REFERENCE.md#when-the-system-does-not-start
mkdir -p "${MNT}/usr/local/lib/arch-os"
render "${data}/session-up.sh" >"${MNT}/usr/local/lib/arch-os/session-up.sh"
chmod 755 "${MNT}/usr/local/lib/arch-os/session-up.sh"
render "${data}/arch-os-session-up.service" >"${MNT}/etc/systemd/system/arch-os-session-up.service"
arch-chroot "$MNT" systemctl enable arch-os-session-up.service

arch-chroot "$MNT" systemctl enable bluetooth.service
arch-chroot "$MNT" systemctl enable avahi-daemon

# avahi's answers arrive as multicast the firewall cannot match to the question,
# so it is let in everywhere; it gives away nothing avahi does not announce.
if [ "$ARCH_OS_FIREWALL_ENABLED" = "true" ]; then
    arch-chroot "$MNT" firewall-offline-cmd --zone=public --add-service=mdns
fi

if [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
    arch-chroot "$MNT" systemctl enable tuned-ppd   # power profiles
    arch-chroot "$MNT" systemctl enable cups.socket # printing
fi

# Out of memory, one app ends instead of the desktop freezing for minutes. GNOME
# starts each app in a scope of its own, so no more than that app is hit. Where
# systemd-oomd(8) recommends, at Fedora's limit for the session.
mkdir -p "${MNT}/etc/systemd/system/-.slice.d" "${MNT}/etc/systemd/system/user@.service.d"
render "${data}/oomd-root.conf" >"${MNT}/etc/systemd/system/-.slice.d/10-arch-os.conf"
render "${data}/oomd-user.conf" >"${MNT}/etc/systemd/system/user@.service.d/10-arch-os.conf"
arch-chroot "$MNT" systemctl enable systemd-oomd.service

# The keyring's ssh agent, which gcr ships off, for every account.
# https://wiki.archlinux.org/title/GNOME/Keyring#SSH_keys
arch-chroot "$MNT" systemctl --global enable gcr-ssh-agent.socket

# ─── Application list ──────────────────────────────────────────────────────
#
# Hidden for every account, from a data directory read before the packages'.
# https://specifications.freedesktop.org/desktop-entry-spec/latest/recognized-keys.html

apps="${MNT}/usr/local/share/applications"
mkdir -p "$apps"
while read -r scope name; do
    case "$scope" in '' | \#*) continue ;; esac
    case "$scope" in
    slim) [ "$ARCH_OS_DESKTOP_SLIM_ENABLED" = "true" ] || continue ;;
    extras) [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ] || continue ;;
    shell) [ "$ARCH_OS_SHELL_ENHANCEMENT_ENABLED" = "true" ] || continue ;;
    esac
    render "${data}/hidden.desktop" >"${apps}/${name}.desktop"
done <"${data}/hidden-apps"

# ─── Settings ──────────────────────────────────────────────────────────────
#
# Defaults every account starts with and may change, as dconf keyfiles beside
# a profile that reads them. https://help.gnome.org/admin/system-admin-guide/stable/dconf-custom-defaults.html

defaults="${MNT}/etc/dconf/db/local.d"
mkdir -p "${MNT}/etc/dconf/profile" "$defaults"
render "${data}/user" >"${MNT}/etc/dconf/profile/user"

keyboard="$layout"
[ -n "$variant" ] && keyboard="${keyboard}+${variant}"
render "${data}/10-arch-os-keyboard" KEYBOARD="$keyboard" >"${defaults}/10-arch-os-keyboard"

if [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
    dock=()
    [ "$ARCH_OS_MANAGER_ENABLED" = "true" ] && dock+=(system-manager.desktop)
    dock+=(org.gnome.Console.desktop)
    [ "$ARCH_OS_BROWSER" != "none" ] && dock+=("$(browser_entry)")
    store=org.gnome.Software.desktop
    [ "$bazaar" = "true" ] && store=io.github.kolunmi.Bazaar.desktop
    dock+=(org.gnome.Nautilus.desktop "$store" org.gnome.Settings.desktop)
    favorites="$(printf "'%s', " "${dock[@]}")"
    render "${data}/20-arch-os-extras" FAVORITES="${favorites%, }" >"${defaults}/20-arch-os-extras"
fi

# The font the shell enhancement's prompt draws with.
if [ "$ARCH_OS_SHELL_ENHANCEMENT_ENABLED" = "true" ]; then
    render "${data}/30-arch-os-shell" >"${defaults}/30-arch-os-shell"
fi

arch-chroot "$MNT" dconf update

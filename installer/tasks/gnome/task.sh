data="$(where)"

# ─── Packages ──────────────────────────────────────────────────────────────
#
# One transaction: pacman resolves packages that replace each other, such as
# pipewire-jack and jack2, only within one.

# Listed explicitly, since services below are enabled for them.
# https://wiki.archlinux.org/title/PipeWire#Installation
packages=(git bluez bluez-utils avahi nss-mdns pipewire pipewire-pulse wireplumber)

# A JACK provider, so a later install such as GNOME Boxes (via qemu-desktop)
# pulls no jack2. ALSA programs through PipeWire too.
packages+=(pipewire-jack pipewire-alsa)

# Realtime priority for PipeWire, which otherwise warns at every login.
packages+=(rtkit)

# gnome-shell's calendar server links against it, but Arch pulls it in only
# through apps the slim desktop leaves out.
packages+=(evolution-data-server)

# Bazaar builds on Flatpak, the same condition as its setting.
bazaar=false
[ "$ARCH_OS_FLATPAK_ENABLED" = "true" ] && [ "$ARCH_OS_BAZAAR_ENABLED" = "true" ] && bazaar=true

# Filtered before the install, so left-out members are never downloaded.
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
# No PackageKit: Arch builds GNOME Software without it, so only pacman changes
# the system.
# https://wiki.archlinux.org/title/Pacman/Tips_and_tricks#Graphical
packages+=("${desktop[@]}")

# Bazaar installs Flatpaks only, so GNOME Firmware takes over the firmware
# updates of GNOME Software.
[ "$bazaar" = "true" ] && packages+=(bazaar gnome-firmware)

# Outside the gnome group since GNOME 51.
packages+=(gnome-extensions-app)

if [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
    # Browser extensions, the power modes in Settings, printing.
    # https://wiki.archlinux.org/title/GNOME#Extensions
    packages+=(gnome-browser-connector power-profiles-daemon cups)

    # xdg-open for the open alias and programs from outside GNOME. The portals
    # come with the group's xdg-desktop-portal-gnome.
    packages+=(xdg-utils)

    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-pipewire lib32-pipewire-jack)

    # NetworkManager handles WireGuard itself. OpenVPN needs the plug-in.
    packages+=(rsync networkmanager-openvpn)

    # AUR builds, firmware updates, common file systems and archives.
    packages+=(base-devel fwupd bash-completion inetutils
        dosfstools ntfs-3g exfatprogs btrfs-progs nfs-utils
        7zip zip unzip unrar wget jq)

    # https://wiki.archlinux.org/title/Codecs_and_containers
    packages+=(ffmpeg ffmpegthumbnailer gstreamer gst-libav gst-plugin-pipewire
        gst-plugins-good gst-plugins-bad gst-plugins-ugly libdvdcss webp-pixbuf-loader)

    packages+=(gamemode)
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-gamemode)

    # All scripts, emoji, metric-compatible families and the terminal font.
    packages+=(noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-liberation ttf-dejavu
        ttf-firacode-nerd)

    packages+=(adw-gtk-theme)
fi

chroot_pacman_install "${packages[@]}"

# Only gamemode: logind grants audio, video and input to the seat's session,
# and the legacy groups break that.
# https://wiki.archlinux.org/title/Users_and_groups#Pre-systemd_groups
[ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ] && arch-chroot "$MNT" gpasswd -a "$ARCH_OS_USERNAME" gamemode

# ─── Name Resolution ───────────────────────────────────────────────────────
#
# <name>.local for printers, shares and other machines. Edited in place, since
# glibc reads no drop-in. https://wiki.archlinux.org/title/Avahi#Hostname_resolution
nsswitch="${MNT}/etc/nsswitch.conf"
if ! grep -q 'mdns_minimal' "$nsswitch"; then
    sed -i '/^hosts:/ s/\bresolve\b/mdns_minimal [NOTFOUND=return] resolve/' "$nsswitch"
    grep -q 'mdns_minimal' "$nsswitch" ||
        echo "unexpected hosts line in /etc/nsswitch.conf, .local names do not resolve" >&2
fi

# ─── Login Screen ──────────────────────────────────────────────────────────
#
# Automatic login only where the LUKS passphrase is the account's password,
# which pam_gdm passes on to the keyring. Otherwise the file stays gdm's.
# https://wiki.archlinux.org/title/GNOME/Keyring#PAM_step
if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && [ "$ARCH_OS_DISK_PASSWORD_ENABLED" != "true" ]; then
    mkdir -p "${MNT}/etc/gdm"
    render "${data}/custom.conf" USERNAME="$ARCH_OS_USERNAME" >"${MNT}/etc/gdm/custom.conf"
fi

# ─── Environment ───────────────────────────────────────────────────────────

mkdir -p "${MNT}/etc/environment.d"
render "${data}/60-arch-os.conf" >"${MNT}/etc/environment.d/60-arch-os.conf"

# Git credentials in the keyring instead of a plain file.
arch-chroot "$MNT" git config --system credential.helper /usr/lib/git-core/git-credential-libsecret

# ─── Keyboard ──────────────────────────────────────────────────────────────
#
# GDM reads this file through localed, the session the dconf default below,
# both with the same layout. https://wiki.archlinux.org/title/Xorg/Keyboard_configuration
layout="$(desktop_layout)"
variant="$(desktop_variant)"
mkdir -p "${MNT}/etc/X11/xorg.conf.d"
render "${data}/00-keyboard.conf" \
    LAYOUT="$layout" \
    MODEL="$ARCH_OS_DESKTOP_KEYBOARD_MODEL" \
    VARIANT="$variant" \
    >"${MNT}/etc/X11/xorg.conf.d/00-keyboard.conf"

# ─── Services ──────────────────────────────────────────────────────────────

arch-chroot "$MNT" systemctl enable gdm.service

# A boot counts as good only once a graphical session is up. A desktop that
# never starts falls through to the fallback entry, then the Recovery:
# docs/REFERENCE.md#fallback
mkdir -p "${MNT}/usr/local/lib/arch-os"
render "${data}/session-up.sh" >"${MNT}/usr/local/lib/arch-os/session-up.sh"
chmod 755 "${MNT}/usr/local/lib/arch-os/session-up.sh"
render "${data}/arch-os-session-up.service" >"${MNT}/etc/systemd/system/arch-os-session-up.service"
arch-chroot "$MNT" systemctl enable arch-os-session-up.service

arch-chroot "$MNT" systemctl enable bluetooth.service
arch-chroot "$MNT" systemctl enable avahi-daemon

# mDNS replies arrive as multicast the firewall cannot match to a query, so
# public lets them in. Nothing leaks that avahi does not announce anyway.
if [ "$ARCH_OS_FIREWALL_ENABLED" = "true" ]; then
    arch-chroot "$MNT" firewall-offline-cmd --zone=public --add-service=mdns
fi

if [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
    arch-chroot "$MNT" systemctl enable power-profiles-daemon.service
    arch-chroot "$MNT" systemctl enable cups.socket
fi

# fwupd ships its refresh timer off, which leaves its metadata stale. Wherever
# fwupd is installed, by Desktop extras or GNOME Firmware.
# https://wiki.archlinux.org/title/Fwupd
if has_command fwupdmgr; then
    arch-chroot "$MNT" systemctl enable fwupd-refresh.timer
fi

# Out of memory, one app ends instead of the desktop freezing, since GNOME runs
# each app in its own scope. Placed as systemd-oomd(8) recommends, with Fedora's
# limit for the session.
mkdir -p "${MNT}/etc/systemd/system/-.slice.d" "${MNT}/etc/systemd/system/user@.service.d"
render "${data}/oomd-root.conf" >"${MNT}/etc/systemd/system/-.slice.d/10-arch-os.conf"
render "${data}/oomd-user.conf" >"${MNT}/etc/systemd/system/user@.service.d/10-arch-os.conf"
arch-chroot "$MNT" systemctl enable systemd-oomd.service

# gcr ships its SSH agent off.
# https://wiki.archlinux.org/title/GNOME/Keyring#SSH_keys
arch-chroot "$MNT" systemctl --global enable gcr-ssh-agent.socket

# ─── Application List ──────────────────────────────────────────────────────
#
# /usr/local/share comes before /usr/share, so these entries mask the packages'.
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
    render "${data}/hidden.desktop" NAME="$name" >"${apps}/${name}.desktop"
done <"${data}/hidden-apps"

# ─── Settings ──────────────────────────────────────────────────────────────
#
# Defaults each account can override, as dconf keyfiles with a profile that
# reads them. https://help.gnome.org/admin/system-admin-guide/stable/dconf-custom-defaults.html

defaults="${MNT}/etc/dconf/db/local.d"
mkdir -p "${MNT}/etc/dconf/profile" "$defaults"
render "${data}/user" >"${MNT}/etc/dconf/profile/user"

# One input source per layout, with the variant at the same place: ru,us and
# phonetic give ru+phonetic and us.
IFS=, read -ra layouts <<<"$layout"
IFS=, read -ra variants <<<"$variant"
sources=""
for i in "${!layouts[@]}"; do
    entry="${layouts[i]}"
    if [ -n "${variants[i]:-}" ]; then
        entry="${entry}+${variants[i]}"
    fi
    sources="${sources:+${sources}, }('xkb', '${entry}')"
done
render "${data}/10-arch-os-keyboard" SOURCES="$sources" >"${defaults}/10-arch-os-keyboard"

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

# A font with the glyphs of the shell enhancement's prompt.
if [ "$ARCH_OS_SHELL_ENHANCEMENT_ENABLED" = "true" ]; then
    render "${data}/30-arch-os-shell" >"${defaults}/30-arch-os-shell"
fi

arch-chroot "$MNT" dconf update

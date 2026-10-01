# The GNOME desktop: packages, login screen, keyboard, services, and what only
# the first login can set.

home="${MNT}/home/${ARCH_OS_USERNAME}"
data="$(where)"
apps="${home}/.local/share/applications"

# Bazaar takes GNOME Software's place only where there is Flatpak to manage.
bazaar_wanted() { [ "$ARCH_OS_FLATPAK_ENABLED" = "true" ] && [ "$ARCH_OS_BAZAAR_ENABLED" = "true" ]; }

# ─── Packages ──────────────────────────────────────────────────────────────
#
# One transaction: packages that replace each other (pipewire-jack and jack2)
# resolve only when pacman sees them together.

# Named outright, since services are switched on for them below.
# https://wiki.archlinux.org/title/PipeWire#Installation
packages=(git bluez bluez-utils avahi nss-mdns pipewire pipewire-pulse wireplumber)

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
    bazaar) bazaar_wanted || continue ;;
    esac
    left_out+=("$name")
done <"${data}/left-out"
mapfile -t desktop < <(printf '%s\n' "${desktop[@]}" | grep -vxF -f <(printf '%s\n' "${left_out[@]}"))
packages+=("${desktop[@]}")

# No PackageKit: Arch builds Software without it and pacman stays the one thing
# that changes the system. https://wiki.archlinux.org/title/Pacman/Tips_and_tricks#Graphical
bazaar_wanted && packages+=(bazaar)
[ "$ARCH_OS_EXTENSION_MANAGER_ENABLED" = "true" ] && packages+=(extension-manager)

if [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
    # https://wiki.archlinux.org/title/GNOME#Extensions
    packages+=(gnome-browser-connector gnome-themes-extra tuned-ppd cups)

    # Portals for flatpaks and screen sharing; GTK's covers what GNOME's lacks.
    packages+=(xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk)

    # The older audio APIs, laptop codec firmware, and rtkit for pipewire's
    # realtime priority, without which it complains at every login.
    packages+=(pipewire-alsa pipewire-jack sof-firmware rtkit)
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-pipewire lib32-pipewire-jack)

    # NetworkManager speaks WireGuard itself; OpenVPN needs the plug-in.
    packages+=(rsync networkmanager-openvpn)

    # Building from the AUR, firmware updates, and opening any drive or archive.
    packages+=(base-devel fwupd bash-completion inetutils
        dosfstools ntfs-3g exfatprogs btrfs-progs nfs-utils
        7zip zip unzip unrar wget jq zenity)

    # Bazaar shows no firmware, so GNOME Firmware is fwupd's window there.
    bazaar_wanted && packages+=(gnome-firmware)

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
# Automatic login behind an encrypted disk only, where the boot password stands
# in front; pam_gdm hands the LUKS passphrase on to the keyring. Written only
# then: the file belongs to gdm. https://wiki.archlinux.org/title/GNOME/Keyring#PAM_step
if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
    mkdir -p "${MNT}/etc/gdm"
    render "${data}/custom.conf" USERNAME="$ARCH_OS_USERNAME" >"${MNT}/etc/gdm/custom.conf"
fi

# ─── The user's environment ────────────────────────────────────────────────

mkdir -p "${home}/.config/environment.d" "${home}/.gnupg" "${apps}"
render "${data}/environment.conf" >"${home}/.config/environment.d/00-arch.conf"
render "${data}/gpg-agent.conf" >"${home}/.gnupg/gpg-agent.conf"

# Git passwords in the keyring rather than in a file.
as_user 'git config --global credential.helper /usr/lib/git-core/git-credential-libsecret'

# ─── Keyboard ──────────────────────────────────────────────────────────────
#
# X11 reads this file, Wayland the setting of the first login; both say the same.
# https://wiki.archlinux.org/title/Xorg/Keyboard_configuration
mkdir -p "${MNT}/etc/X11/xorg.conf.d"
render "${data}/00-keyboard.conf" \
    LAYOUT="$ARCH_OS_DESKTOP_KEYBOARD_LAYOUT" \
    MODEL="$ARCH_OS_DESKTOP_KEYBOARD_MODEL" \
    VARIANT="$ARCH_OS_DESKTOP_KEYBOARD_VARIANT" \
    >"${MNT}/etc/X11/xorg.conf.d/00-keyboard.conf"

keyboard="$ARCH_OS_DESKTOP_KEYBOARD_LAYOUT"
[ -n "$ARCH_OS_DESKTOP_KEYBOARD_VARIANT" ] && keyboard="${keyboard}+${ARCH_OS_DESKTOP_KEYBOARD_VARIANT}"
on_first_login <<FIRST
gsettings set org.gnome.desktop.input-sources sources "[('xkb', '${keyboard}')]"
FIRST

# ─── Services ──────────────────────────────────────────────────────────────

arch-chroot "$MNT" systemctl enable gdm.service
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

# The keyring's ssh agent, which gcr ships off, for every account.
# https://wiki.archlinux.org/title/GNOME/Keyring#SSH_keys
arch-chroot "$MNT" systemctl --global enable gcr-ssh-agent.socket

# ─── Application list ──────────────────────────────────────────────────────

while read -r scope name; do
    case "$scope" in '' | \#*) continue ;; esac
    case "$scope" in
    extras) [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ] || continue ;;
    shell) [ "$ARCH_OS_SHELL_ENHANCEMENT_ENABLED" = "true" ] || continue ;;
    extension-manager) [ "$ARCH_OS_EXTENSION_MANAGER_ENABLED" = "true" ] || continue ;;
    esac
    render "${data}/hidden.desktop" >"${apps}/${name}.desktop"
done <"${data}/hidden-apps"

# ─── First login ───────────────────────────────────────────────────────────

if [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
    dock=()
    [ "$ARCH_OS_MANAGER_ENABLED" = "true" ] && dock+=(arch-os.desktop)
    dock+=(org.gnome.Console.desktop)
    [ "$ARCH_OS_BROWSER" != "none" ] && dock+=("$(browser_entry)")
    dock+=(org.gnome.Nautilus.desktop)
    if bazaar_wanted; then
        dock+=(io.github.kolunmi.Bazaar.desktop)
    else
        dock+=(org.gnome.Software.desktop)
    fi
    dock+=(org.gnome.Settings.desktop)
    favorites="$(printf "'%s', " "${dock[@]}")"
    favorites="${favorites%, }"
    on_first_login <<FIRST
gsettings set org.gnome.shell favorite-apps "[${favorites}]"
dconf reset -f /org/gnome/desktop/app-folders/
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
gsettings set org.gnome.desktop.interface accent-color 'slate'
gsettings set org.gnome.desktop.interface font-hinting 'slight'
gsettings set org.gnome.desktop.interface font-antialiasing 'rgba'
gsettings set org.gnome.desktop.input-sources show-all-sources true
gsettings set org.gnome.mutter center-new-windows true
gsettings set org.gtk.Settings.FileChooser sort-directories-first true
gsettings set org.gtk.gtk4.Settings.FileChooser sort-directories-first true
gsettings set org.gnome.desktop.wm.keybindings close "['<Super>q']"
gsettings set org.gnome.desktop.wm.keybindings minimize "['<Super>h']"
gsettings set org.gnome.desktop.wm.keybindings show-desktop "['<Super>d']"
gsettings set org.gnome.desktop.wm.keybindings toggle-fullscreen "['<Super>F11']"
FIRST
fi

own_home

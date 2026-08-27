# The GNOME desktop: the packages, the login screen, the keyboard, and the
# settings that only the first login can apply.

simulating && return 0

home="${MNT}/home/${ARCH_OS_USERNAME}"
data="$(where)"
apps="${home}/.local/share/applications"

# ─── Packages ────────────────────────────────────────────────────────────────
# Installed in one transaction rather than in groups: packages that replace each
# other — pipewire-jack and jack2 — can only be resolved when pacman sees them
# together.
packages=(gnome git)

# Named outright rather than relied on as dependencies of the gnome group, since
# services are switched on for them below.
packages+=(bluez bluez-utils avahi)

if [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
    packages+=(gnome-browser-connector gnome-themes-extra tuned-ppd cups gnome-epub-thumbnailer)

    # Screen sharing, portals and flatpak integration on Wayland.
    packages+=(xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome flatpak-xdg-utils)

    # Audio. https://wiki.archlinux.org/title/PipeWire#Installation
    packages+=(pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber sof-firmware)
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-pipewire lib32-pipewire-jack)

    # Reaching other machines, and letting them reach this one.
    packages+=(samba rsync gvfs gvfs-mtp gvfs-smb gvfs-nfs gvfs-afc gvfs-goa gvfs-gphoto2 gvfs-dnssd gvfs-wsdd)
    packages+=(modemmanager network-manager-sstp networkmanager-l2tp networkmanager-vpnc
        networkmanager-openvpn networkmanager-openconnect networkmanager-strongswan rygel)

    packages+=("${ARCH_OS_KERNEL}-headers")

    # File systems and archives, so a drive from anywhere else opens.
    packages+=(base-devel archlinux-contrib pacutils fwupd bash-completion inetutils nfs-utils
        e2fsprogs f2fs-tools udftools dosfstools ntfs-3g exfatprogs btrfs-progs xfsprogs
        7zip zip unzip unrar tar wget curl nautilus-image-converter ca-certificates)

    packages+=(gdb python go rust nodejs npm lua cmake jq zenity gum fzf)

    # Codecs. https://wiki.archlinux.org/title/Codecs_and_containers
    packages+=(ffmpeg ffmpegthumbnailer gstreamer gst-libav gst-plugin-pipewire gst-plugins-good
        gst-plugins-bad gst-plugins-ugly libdvdcss libheif webp-pixbuf-loader opus speex
        libvpx libwebp jasper libmad)

    # No lib32 build of libvpx, libwebp, sdl2-compat or sdl12-compat exists —
    # only gamemode itself is shipped 32 bit.
    packages+=(gamemode sdl3_image sdl2-compat sdl12-compat)
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-gamemode)

    packages+=(ttf-firacode-nerd ttf-nerd-fonts-symbols woff2-font-awesome noto-fonts noto-fonts-cjk
        noto-fonts-emoji ttf-liberation ttf-dejavu adobe-source-sans-fonts adobe-source-serif-fonts)

    packages+=(adw-gtk-theme tela-circle-icon-theme-standard)
fi

[ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && [ "$ARCH_OS_BTRFS_ASSISTANT_ENABLED" = "true" ] && packages+=(btrfs-assistant)

chroot_pacman_install "${packages[@]}"

if [ "$ARCH_OS_DESKTOP_SLIM_ENABLED" = "true" ]; then
    while read -r pkg; do
        case "$pkg" in '' | \#*) continue ;; esac
        chroot_pacman_remove "$pkg" || true
    done <"${data}/slim-remove"
fi

# ─── Groups ──────────────────────────────────────────────────────────────────
# https://wiki.archlinux.org/title/Users_and_groups#User_groups
arch-chroot "$MNT" groupadd -f plugdev
arch-chroot "$MNT" usermod -aG adm,audio,video,optical,input,tty,plugdev "$ARCH_OS_USERNAME"
[ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ] && arch-chroot "$MNT" gpasswd -a "$ARCH_OS_USERNAME" gamemode

# ─── Login screen ────────────────────────────────────────────────────────────
mkdir -p "${MNT}/etc/gdm"
{
    echo '[daemon]'
    echo 'WaylandEnable=True'
    if [ "$ARCH_OS_DESKTOP_AUTOLOGIN_ENABLED" = "true" ]; then
        echo
        echo 'AutomaticLoginEnable=True'
        echo "AutomaticLogin=${ARCH_OS_USERNAME}"
    fi
    echo
    echo '[debug]'
    echo 'Enable=False'
} >"${MNT}/etc/gdm/custom.conf"

# The login password also unlocks the keyring, so nothing asks twice.
sed -i 's/auth\s\+optional\s\+pam_gnome_keyring\.so$/& try_first_pass/' "${MNT}/etc/pam.d/gdm-password"

# Under automatic login GDM never sees a password, so PAM has none to unlock the
# keyring with. It is created empty now, before the first boot, rather than from
# the first-login script — that would race GDM's own PAM hook, which runs on the
# same login before anything of ours gets a turn. The data is still behind disk
# encryption wherever this applies by default.
if [ "$ARCH_OS_DESKTOP_AUTOLOGIN_ENABLED" = "true" ]; then
    as_user 'dbus-run-session -- gnome-keyring-daemon --unlock <<< ""' ||
        echo "could not pre-create a passwordless login keyring"
fi

# ─── The user's environment ──────────────────────────────────────────────────
mkdir -p "${home}/.config/environment.d" "${home}/.gnupg" "${apps}"
cp "${data}/environment.conf" "${home}/.config/environment.d/00-arch.conf"
echo 'pinentry-program /usr/bin/pinentry-gnome3' >"${home}/.gnupg/gpg-agent.conf"

# Git passwords in the keyring rather than in a file.
as_user 'git config --global credential.helper /usr/lib/git-core/git-credential-libsecret'

# ─── Keyboard ────────────────────────────────────────────────────────────────
# X11 applications read this file; Wayland reads the setting written at first
# login below. Both are needed, and both say the same thing.
mkdir -p "${MNT}/etc/X11/xorg.conf.d"
{
    echo 'Section "InputClass"'
    echo '    Identifier "system-keyboard"'
    echo '    MatchIsKeyboard "yes"'
    echo "    Option \"XkbLayout\" \"${ARCH_OS_DESKTOP_KEYBOARD_LAYOUT}\""
    echo "    Option \"XkbModel\" \"${ARCH_OS_DESKTOP_KEYBOARD_MODEL}\""
    echo "    Option \"XkbVariant\" \"${ARCH_OS_DESKTOP_KEYBOARD_VARIANT}\""
    echo 'EndSection'
} >"${MNT}/etc/X11/xorg.conf.d/00-keyboard.conf"

keyboard="$ARCH_OS_DESKTOP_KEYBOARD_LAYOUT"
[ -n "$ARCH_OS_DESKTOP_KEYBOARD_VARIANT" ] && keyboard="${keyboard}+${ARCH_OS_DESKTOP_KEYBOARD_VARIANT}"
on_first_login <<FIRST
gsettings set org.gnome.desktop.input-sources sources "[('xkb', '${keyboard}')]"
FIRST

# ─── Services ────────────────────────────────────────────────────────────────
arch-chroot "$MNT" systemctl enable gdm.service
arch-chroot "$MNT" systemctl enable bluetooth.service
arch-chroot "$MNT" systemctl enable avahi-daemon

if [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
    arch-chroot "$MNT" systemctl enable tuned-ppd   # power profiles
    arch-chroot "$MNT" systemctl enable cups.socket # printing
fi

# For every user rather than for this one: --global writes to /etc/systemd/user
# and keeps working when a unit is renamed. The sockets follow through Also=.
arch-chroot "$MNT" systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service gcr-ssh-agent.socket

# ─── Application list ────────────────────────────────────────────────────────
hide() {
    printf '[Desktop Entry]\nType=Application\nHidden=true\n' >"${apps}/${1}.desktop"
}
while read -r scope name; do
    case "$scope" in '' | \#*) continue ;; esac
    case "$scope" in
    extras) [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ] || continue ;;
    shell) [ "$ARCH_OS_SHELL_ENHANCEMENT_ENABLED" = "true" ] || continue ;;
    esac
    hide "$name"
done <"${data}/hidden-apps"

# The snapshot browser under a name that says what it is for. A file of the same
# name in the user's own applications folder wins over the one in /usr.
if [ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && [ "$ARCH_OS_BTRFS_ASSISTANT_ENABLED" = "true" ]; then
    {
        echo '[Desktop Entry]'
        echo 'Name=Snapshots'
        echo 'Comment=Browse and restore system snapshots'
        echo 'Exec=btrfs-assistant-launcher'
        echo 'Terminal=false'
        echo 'Type=Application'
        echo 'Icon=deja-dup'
        echo 'Categories=System'
        echo 'NoDisplay=false'
    } >"${apps}/btrfs-assistant.desktop"
fi

# Let flatpaks read the desktop theme, so they do not stand out as light windows
# on a dark desktop.
arch-chroot "$MNT" flatpak override --filesystem=xdg-config/gtk-3.0
arch-chroot "$MNT" flatpak override --filesystem=xdg-config/gtk-4.0

# ─── What only the first login can do ────────────────────────────────────────
if [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
    on_first_login <<'FIRST'
gsettings set org.gnome.shell favorite-apps "['org.gnome.Console.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Software.desktop', 'org.gnome.Settings.desktop']"
dconf reset -f /org/gnome/desktop/app-folders/
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
gsettings set org.gnome.desktop.interface icon-theme 'Tela-circle'
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

arch-chroot "$MNT" chown -R "${ARCH_OS_USERNAME}:${ARCH_OS_USERNAME}" "/home/${ARCH_OS_USERNAME}"

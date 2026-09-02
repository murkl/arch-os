# The GNOME desktop: the packages, the login screen, the keyboard, and the
# settings that only the first login can apply.

simulating && return 0

home="${MNT}/home/${ARCH_OS_USERNAME}"
data="$(where)"
apps="${home}/.local/share/applications"

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# PACKAGES
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# One transaction rather than several: packages that replace each other
# (pipewire-jack and jack2) can only be resolved when pacman sees them together.

# Named outright rather than left to the group, because services are switched
# on for them below.
packages=(git bluez bluez-utils avahi)

# The group, filtered, rather than the group and a round of removals: what the
# slim desktop leaves out is never downloaded, and a member another member
# really depends on still arrives as a dependency.
mapfile -t desktop < <(arch-chroot "$MNT" pacman -Sgq gnome)
[ "${#desktop[@]}" -gt 0 ] || {
    echo "the gnome package group is empty" >&2
    exit 1
}
if [ "$ARCH_OS_DESKTOP_SLIM_ENABLED" = "true" ]; then
    mapfile -t desktop < <(printf '%s\n' "${desktop[@]}" |
        grep -vxF -f <(grep -vE '^(#|[[:space:]]*$)' "${data}/slim-exclude"))
fi
packages+=("${desktop[@]}")

if [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
    packages+=(gnome-browser-connector gnome-themes-extra tuned-ppd cups)

    # Portals, for flatpaks and screen sharing on Wayland. The GNOME portal
    # itself is in the group; the GTK one is the fallback for what it does not
    # implement.
    packages+=(xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk)

    # Audio. https://wiki.archlinux.org/title/PipeWire#Installation
    packages+=(pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber sof-firmware)
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-pipewire lib32-pipewire-jack)

    # Reaching other machines, and letting them reach this one. The gvfs back
    # ends are in the group, and NetworkManager speaks WireGuard by itself, so
    # OpenVPN is the one protocol still worth a plug-in nobody has to look for.
    # The rest of the VPN plug-ins are a package away for whoever needs them.
    packages+=(rsync networkmanager-openvpn)

    # base-devel is what builds from the AUR; the rest opens a drive or an
    # archive from anywhere else. The file systems are the ones a stick or an
    # external drive actually turns up formatted as.
    packages+=(base-devel fwupd bash-completion inetutils
        dosfstools ntfs-3g exfatprogs btrfs-progs nfs-utils
        7zip zip unzip unrar wget jq zenity)

    # Codecs. https://wiki.archlinux.org/title/Codecs_and_containers
    packages+=(ffmpeg ffmpegthumbnailer gstreamer gst-libav gst-plugin-pipewire
        gst-plugins-good gst-plugins-bad gst-plugins-ugly libdvdcss webp-pixbuf-loader)

    # gamemode alone: the SDL compatibility libraries arrive as dependencies of
    # the games that need them, and only gamemode is shipped 32 bit anyway.
    packages+=(gamemode)
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-gamemode)

    # One family that covers every script the web has, one that draws emoji,
    # two metric-compatible with what documents ask for, and the terminal font
    # the prompt is drawn with.
    packages+=(noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-liberation ttf-dejavu
        ttf-firacode-nerd)

    packages+=(adw-gtk-theme tela-circle-icon-theme-standard)
fi

[ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && [ "$ARCH_OS_BTRFS_ASSISTANT_ENABLED" = "true" ] && packages+=(btrfs-assistant)

chroot_pacman_install "${packages[@]}"

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# GROUPS
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# https://wiki.archlinux.org/title/Users_and_groups#User_groups
arch-chroot "$MNT" groupadd -f plugdev
arch-chroot "$MNT" usermod -aG adm,audio,video,optical,input,tty,plugdev "$ARCH_OS_USERNAME"
[ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ] && arch-chroot "$MNT" gpasswd -a "$ARCH_OS_USERNAME" gamemode

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# LOGIN SCREEN
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# Only written where there is something to say. /etc/gdm/custom.conf belongs
# to the gdm package, so a copy of it that only repeats gdm's own defaults
# (Wayland on, debugging off) would just be a file to merge after every
# update, for nothing gained. GDM unlocks the login keyring from the password
# it was given itself, so there's nothing to arrange for that either.
if [ "$ARCH_OS_DESKTOP_AUTOLOGIN_ENABLED" = "true" ]; then
    mkdir -p "${MNT}/etc/gdm"
    {
        echo '# Written by the Arch OS Installer.'
        echo '[daemon]'
        echo 'AutomaticLoginEnable=True'
        echo "AutomaticLogin=${ARCH_OS_USERNAME}"
    } >"${MNT}/etc/gdm/custom.conf"
fi

# Under automatic login GDM never sees a password, so PAM has none to unlock
# the keyring with. GNOME's own answer is a login keyring without a password:
# the daemon opens it at the start of the session and nothing ever asks. The
# data is still behind disk encryption wherever that applies by default.
#
# Created here rather than from the first-login script, which would race
# GDM's own PAM hook on the same login.
# https://wiki.archlinux.org/title/GNOME/Keyring#Passwords_are_not_remembered
if [ "$ARCH_OS_DESKTOP_AUTOLOGIN_ENABLED" = "true" ]; then
    keyrings="/home/${ARCH_OS_USERNAME}/.local/share/keyrings"

    # The daemon needs a session bus and a runtime directory, and there is
    # neither inside a chroot. /tmp is a tmpfs arch-chroot mounts itself, so
    # none of this reaches the installed system.
    runtime="/tmp/keyring"
    arch-chroot "$MNT" install -d -m 700 -o "$ARCH_OS_USERNAME" -g "$ARCH_OS_USERNAME" "$runtime"
    as_user "XDG_RUNTIME_DIR=${runtime} dbus-run-session -- gnome-keyring-daemon --unlock <<< ''" || true

    # It forks before it has written the keyring, so the file exists a moment
    # before it actually holds one.
    for _ in $(seq 50); do
        [ -s "${MNT}${keyrings}/login.keyring" ] && break
        sleep 0.1
    done

    if [ -s "${MNT}${keyrings}/login.keyring" ]; then
        echo "created a passwordless login keyring"
    else
        echo "could not pre-create a passwordless login keyring, the desktop will ask for one on first use" >&2
    fi

    # It stays behind once it's done, and a process of the target still
    # running is a mount that will not come down at the end.
    arch-chroot "$MNT" pkill -u "$ARCH_OS_USERNAME" -x gnome-keyring-d || true
fi

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# THE USER'S ENVIRONMENT
# ////////////////////////////////////////////////////////////////////////////////////////////////////

mkdir -p "${home}/.config/environment.d" "${home}/.gnupg" "${apps}"
cp "${data}/environment.conf" "${home}/.config/environment.d/00-arch.conf"
echo 'pinentry-program /usr/bin/pinentry-gnome3' >"${home}/.gnupg/gpg-agent.conf"

# Git passwords in the keyring rather than in a file.
as_user 'git config --global credential.helper /usr/lib/git-core/git-credential-libsecret'

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# KEYBOARD
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# X11 applications read this file, Wayland the setting written at first login.
# Both are needed, and both say the same thing.
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

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# SERVICES
# ////////////////////////////////////////////////////////////////////////////////////////////////////

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

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# APPLICATION LIST
# ////////////////////////////////////////////////////////////////////////////////////////////////////

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

# The snapshot browser under a name that says what it's for. A file of the
# same name in the user's own applications folder wins over the one in /usr.
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

# Let flatpaks read the desktop theme, so they don't stand out as light
# windows on a dark desktop.
arch-chroot "$MNT" flatpak override --filesystem=xdg-config/gtk-3.0
arch-chroot "$MNT" flatpak override --filesystem=xdg-config/gtk-4.0

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# WHAT ONLY THE FIRST LOGIN CAN DO
# ////////////////////////////////////////////////////////////////////////////////////////////////////

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

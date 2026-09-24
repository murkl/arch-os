# The GNOME desktop: the packages, the login screen, the keyboard, and the
# settings that only the first login can apply.

home="${MNT}/home/${ARCH_OS_USERNAME}"
data="$(where)"
apps="${home}/.local/share/applications"

# ////////////////////////////////////////////////////////////////////////////
# PACKAGES
# ////////////////////////////////////////////////////////////////////////////

# One transaction rather than several: packages that replace each other
# (pipewire-jack and jack2) can only be resolved when pacman sees them together.

# Named outright rather than left to the group, because services are switched on
# for them below. The group pulls pipewire in only as somebody else's
# dependency, which leaves the session manager out.
# https://wiki.archlinux.org/title/PipeWire#Installation
packages=(git bluez bluez-utils avahi nss-mdns pipewire pipewire-pulse wireplumber)

# The group filtered rather than installed and then trimmed: what the slim
# desktop leaves out is never downloaded.
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

    # For flatpaks and screen sharing on Wayland. The GNOME portal is in the
    # group; the GTK one is the fallback for what it does not implement.
    packages+=(xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk)

    # What the audio stack needs to stand in for the two APIs older software
    # still opens, and the firmware many laptop codecs need. rtkit is what hands
    # pipewire the realtime priority it asks for, and the portal the desktop
    # offers it through - without it both say so at every login and the audio
    # thread runs at ordinary priority.
    packages+=(pipewire-alsa pipewire-jack sof-firmware rtkit)
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-pipewire lib32-pipewire-jack)

    # NetworkManager speaks WireGuard by itself, so OpenVPN is the one protocol
    # still worth a plug-in nobody has to look for.
    packages+=(rsync networkmanager-openvpn)

    # base-devel builds from the AUR; the rest opens a drive or an archive from
    # anywhere else.
    packages+=(base-devel fwupd bash-completion inetutils
        dosfstools ntfs-3g exfatprogs btrfs-progs nfs-utils
        7zip zip unzip unrar wget jq zenity)

    # Codecs. https://wiki.archlinux.org/title/Codecs_and_containers
    packages+=(ffmpeg ffmpegthumbnailer gstreamer gst-libav gst-plugin-pipewire
        gst-plugins-good gst-plugins-bad gst-plugins-ugly libdvdcss webp-pixbuf-loader)

    # gamemode alone: the SDL compatibility libraries arrive as dependencies of
    # the games that need them.
    packages+=(gamemode)
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-gamemode)

    # One family for every script the web has, one for emoji, two metric-
    # compatible with what documents ask for, and the terminal font.
    packages+=(noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-liberation ttf-dejavu
        ttf-firacode-nerd)

    packages+=(adw-gtk-theme)
fi

chroot_pacman_install "${packages[@]}"

# ////////////////////////////////////////////////////////////////////////////
# GROUPS
# ////////////////////////////////////////////////////////////////////////////

# Only gamemode, whose limits are granted to the group. Sound, video, drives and
# input devices are handed to whoever sits at the seat by logind, and the groups
# that used to grant them do harm now: audio lets one session hold the sound card
# against the next, input reads every keystroke on the machine, tty writes to
# every other terminal. The journal is readable by wheel already.
# https://wiki.archlinux.org/title/Users_and_groups#Pre-systemd_groups
[ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ] && arch-chroot "$MNT" gpasswd -a "$ARCH_OS_USERNAME" gamemode

# ////////////////////////////////////////////////////////////////////////////
# NAME RESOLUTION
# ////////////////////////////////////////////////////////////////////////////

# The avahi daemon switched on further down announces this machine and finds
# the others, and without this nothing on the system can then reach any of them
# by the name they answer to: a printer, a share and another machine are all
# <name>.local. The module goes in front of the resolver that would answer
# NOTFOUND for that suffix and end the lookup there.
#
# An edit rather than a drop-in: the hosts line is one line of one file, glibc
# reads no directory beside it, and the file belongs to the filesystem package.
# https://wiki.archlinux.org/title/Avahi#Hostname_resolution
nsswitch="${MNT}/etc/nsswitch.conf"
if ! grep -q 'mdns_minimal' "$nsswitch"; then
    sed -i '/^hosts:/ s/\bresolve\b/mdns_minimal [NOTFOUND=return] resolve/' "$nsswitch"
    grep -q 'mdns_minimal' "$nsswitch" ||
        echo "the hosts line in /etc/nsswitch.conf is not the one this Arch ships, .local names will not resolve" >&2
fi

# ////////////////////////////////////////////////////////////////////////////
# LOGIN SCREEN
# ////////////////////////////////////////////////////////////////////////////

# Automatic login behind an encrypted disk, and nowhere else: the password at
# boot already stands in front of the desktop, and without encryption the login
# screen is the only protection there is.
#
# GDM then never sees a password, and PAM would have none to unlock the login
# keyring with - except that systemd-cryptsetup leaves the LUKS passphrase in
# the kernel keyring and pam_gdm hands it on.
# https://wiki.archlinux.org/title/GNOME/Keyring#PAM_step
#
# Only written where there is something to say: /etc/gdm/custom.conf belongs to
# the gdm package, and a copy repeating its defaults is a file to merge after
# every update for nothing gained.
if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
    mkdir -p "${MNT}/etc/gdm"
    render "${data}/custom.conf" USERNAME="$ARCH_OS_USERNAME" >"${MNT}/etc/gdm/custom.conf"
fi

# ////////////////////////////////////////////////////////////////////////////
# THE USER'S ENVIRONMENT
# ////////////////////////////////////////////////////////////////////////////

mkdir -p "${home}/.config/environment.d" "${home}/.gnupg" "${apps}"
render "${data}/environment.conf" >"${home}/.config/environment.d/00-arch.conf"
render "${data}/gpg-agent.conf" >"${home}/.gnupg/gpg-agent.conf"

# Git passwords in the keyring rather than in a file.
as_user 'git config --global credential.helper /usr/lib/git-core/git-credential-libsecret'

# ////////////////////////////////////////////////////////////////////////////
# KEYBOARD
# ////////////////////////////////////////////////////////////////////////////

# X11 applications read this file, Wayland the setting written at first login.
# Both are needed, and both say the same thing.
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

# ////////////////////////////////////////////////////////////////////////////
# SERVICES
# ////////////////////////////////////////////////////////////////////////////

arch-chroot "$MNT" systemctl enable gdm.service
arch-chroot "$MNT" systemctl enable bluetooth.service
arch-chroot "$MNT" systemctl enable avahi-daemon

# The answers avahi asks for arrive as multicast on its own port, which the
# firewall cannot match to the question that went out. Without this the printers
# and shares it looks for never show up.
if [ "$ARCH_OS_FIREWALL_ENABLED" = "true" ]; then
    arch-chroot "$MNT" firewall-offline-cmd --add-service=mdns
fi

if [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
    arch-chroot "$MNT" systemctl enable tuned-ppd   # power profiles
    arch-chroot "$MNT" systemctl enable cups.socket # printing
fi

# The keyring's ssh agent, which gcr ships switched off. PipeWire and
# WirePlumber switch themselves on when they are installed. --global writes to
# /etc/systemd/user, so it holds for every account.
# https://wiki.archlinux.org/title/GNOME/Keyring#SSH_keys
arch-chroot "$MNT" systemctl --global enable gcr-ssh-agent.socket

# ////////////////////////////////////////////////////////////////////////////
# APPLICATION LIST
# ////////////////////////////////////////////////////////////////////////////

hide() {
    render "${data}/hidden.desktop" >"${apps}/${1}.desktop"
}
while read -r scope name; do
    case "$scope" in '' | \#*) continue ;; esac
    case "$scope" in
    extras) [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ] || continue ;;
    shell) [ "$ARCH_OS_SHELL_ENHANCEMENT_ENABLED" = "true" ] || continue ;;
    esac
    hide "$name"
done <"${data}/hidden-apps"

# ////////////////////////////////////////////////////////////////////////////
# WHAT ONLY THE FIRST LOGIN CAN DO
# ////////////////////////////////////////////////////////////////////////////

if [ "$ARCH_OS_DESKTOP_EXTRAS_ENABLED" = "true" ]; then
    favorites="'org.gnome.Console.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Software.desktop', 'org.gnome.Settings.desktop'"
    [ "$ARCH_OS_MANAGER_ENABLED" = "true" ] && favorites="'arch-os.desktop', ${favorites}"
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

# Browser extensions, printing.
# https://wiki.archlinux.org/title/GNOME#Extensions
packages=(gnome-browser-connector cups)

# xdg-open for the open alias and programs from outside GNOME. The portals
# come with the group's xdg-desktop-portal-gnome.
packages+=(xdg-utils)

# NetworkManager handles WireGuard itself. OpenVPN needs the plug-in.
packages+=(rsync networkmanager-openvpn)

# AUR builds, firmware updates, common file systems and archives.
packages+=(base-devel fwupd bash-completion inetutils
    ntfsprogs exfatprogs nfs-utils
    7zip zip unzip unrar wget jq)

# GStreamer decodes on the GPU through gst-plugin-va.
# https://wiki.archlinux.org/title/Codecs_and_containers
packages+=(ffmpeg gstreamer gst-libav gst-plugin-va
    gst-plugins-good gst-plugins-bad gst-plugins-ugly)

packages+=(gamemode)
[ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=(lib32-gamemode)

# All scripts, emoji, metric-compatible families and the terminal font.
packages+=(noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-liberation ttf-dejavu
    ttf-firacode-nerd)

# The GTK 3 theme the gnome task's defaults name.
packages+=(adw-gtk-theme)

chroot_pacman_install "${packages[@]}"

# Only gamemode: logind grants audio, video and input to the seat's session,
# and the legacy groups break that.
# https://wiki.archlinux.org/title/Users_and_groups#Pre-systemd_groups
run arch-chroot "$MNT" gpasswd -a "$ARCH_OS_USERNAME" gamemode

run arch-chroot "$MNT" systemctl enable cups.socket

# fwupd ships its refresh timer off, which leaves its metadata stale.
# https://wiki.archlinux.org/title/Fwupd
run arch-chroot "$MNT" systemctl enable fwupd-refresh.timer

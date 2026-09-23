# Applications from Flathub, installed and updated through Software like any
# other. The package brings Flathub as a remote of its own, so nothing is added.
# https://wiki.archlinux.org/title/Flatpak

# gnome-software only recommends it, so the group never pulls it in.
chroot_pacman_install flatpak

# So flatpaks read the desktop theme rather than standing out as light windows
# on a dark desktop.
arch-chroot "$MNT" flatpak override --filesystem=xdg-config/gtk-3.0
arch-chroot "$MNT" flatpak override --filesystem=xdg-config/gtk-4.0

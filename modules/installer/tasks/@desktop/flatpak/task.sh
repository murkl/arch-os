# Applications from Flathub, installed and updated through Bazaar, a store made
# for Flatpak. The package brings Flathub as a remote of its own, so nothing is
# added, and Bazaar is started over D-Bus when it is first needed.
# https://wiki.archlinux.org/title/Flatpak

chroot_pacman_install flatpak bazaar

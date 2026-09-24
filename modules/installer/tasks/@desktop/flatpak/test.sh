# The theme reaches every flatpak, and there is somewhere to install one from:
# Flathub comes with the package rather than from here, which is a promise of
# the package this reads back.

grep -q 'xdg-config/gtk-4.0' "${MNT}/var/lib/flatpak/overrides/global"
remotes="$(arch-chroot "$MNT" flatpak remotes --system --columns=name)"
grep -qx flathub <<<"$remotes"

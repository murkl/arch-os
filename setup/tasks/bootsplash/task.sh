# Show a logo while the system starts instead of a wall of kernel messages.

simulating && return 0

chroot_pacman_install plymouth git base-devel

# The hook has to run early enough to have a screen to draw on, which is
# directly behind whichever of base's init hooks is in use. Matched that way
# rather than against the whole line, so the hook still lands when the rest of
# the list changes — a splash that is silently left out looks exactly like one
# that does not work.
sed -i 's/^HOOKS=(\(base [a-z]*\)/HOOKS=(\1 plymouth/' "${MNT}/etc/mkinitcpio.conf"
if ! grep -qE '^HOOKS=\(.*\bplymouth\b' "${MNT}/etc/mkinitcpio.conf"; then
    echo "plymouth could not be added to the mkinitcpio hooks" >&2
    exit 1
fi

chroot_aur_install plymouth-theme-arch-os

# -R rebuilds the ram disk, which is what actually puts the theme in it.
arch-chroot "$MNT" plymouth-set-default-theme -R arch-os

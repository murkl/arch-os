# A logo while the system starts instead of a wall of kernel messages.
# https://wiki.archlinux.org/title/Plymouth

chroot_pacman_install plymouth

# Directly behind the init hook, which is early enough to have a screen to draw
# on. mkinitcpio sources its own file and every drop-in as one, so this splices
# the array the initramfs task set rather than matching a line with a pattern.
mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
render "$(where)/20-plymouth.conf" >"${MNT}/etc/mkinitcpio.conf.d/20-plymouth.conf"

# The theme comes from the AUR, which can be out of reach. Without it Plymouth
# draws its own default, so the ram disk is rebuilt either way and a missing
# theme is reported at the very end, rather than leaving a hook in the
# configuration that no image was ever built with.
themed=true
if chroot_aur_install plymouth-theme-arch-os; then
    # Split rather than `plymouth-set-default-theme -R`, which ends on `exit 0`
    # whatever mkinitcpio made of the rebuild.
    arch-chroot "$MNT" plymouth-set-default-theme arch-os
else
    themed=false
fi
arch-chroot "$MNT" mkinitcpio -P
[ "$themed" = "true" ]

# https://wiki.archlinux.org/title/Plymouth
chroot_pacman_install plymouth

# After base and systemd in the hooks of the bootloader task.
mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
render "$(where)/20-plymouth.conf" >"${MNT}/etc/mkinitcpio.conf.d/20-plymouth.conf"

# Rebuilt even without the theme, so no image lacks the hook, and the failure
# comes last. Not `plymouth-set-default-theme -R`, which always exits 0.
themed=true
if chroot_aur_install plymouth-theme-arch-os; then
    arch-chroot "$MNT" plymouth-set-default-theme arch-os
else
    themed=false
fi
arch-chroot "$MNT" mkinitcpio -P
[ "$themed" = "true" ]

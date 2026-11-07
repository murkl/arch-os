# https://wiki.archlinux.org/title/Plymouth
chroot_pacman_install plymouth

# After base and systemd in the hooks of the bootloader task.
run mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
render "$(where)/20-plymouth.conf" | write_file "${MNT}/etc/mkinitcpio.conf.d/20-plymouth.conf"

# Rebuilt even without the theme, so no image lacks the hook, and the failure
# comes last. Not `plymouth-set-default-theme -R`, which always exits 0.
themed=true
if chroot_aur_install plymouth-theme-arch-os; then
    run arch-chroot "$MNT" plymouth-set-default-theme arch-os
else
    themed=false
fi
run arch-chroot "$MNT" mkinitcpio -P
[ "$themed" = "true" ]

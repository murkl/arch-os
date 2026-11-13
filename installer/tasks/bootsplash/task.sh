# https://wiki.archlinux.org/title/Plymouth
chroot_pacman_install plymouth

# After base and systemd in the hooks of the bootloader task.
run mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
render "$(where)/20-plymouth.conf" | write_file "${MNT}/etc/mkinitcpio.conf.d/20-plymouth.conf"

# Rebuilt even without the theme, so no image lacks the hook, and the failure
# comes last. In a subshell, since an unreachable AUR ends the build's shell.
# Not `plymouth-set-default-theme -R`, which always exits 0.
failed=0
(chroot_aur_install plymouth-theme-arch-os) || failed=$?
if [ "$failed" -eq 0 ]; then
    run arch-chroot "$MNT" plymouth-set-default-theme arch-os
fi
run arch-chroot "$MNT" mkinitcpio -P
[ "$failed" -eq 0 ] || exit "$failed"

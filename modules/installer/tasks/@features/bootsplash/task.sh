# A logo while the system starts. https://wiki.archlinux.org/title/Plymouth
chroot_pacman_install plymouth

# Spliced into the hooks the loader set, right behind the init hook.
mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
render "$(where)/20-plymouth.conf" >"${MNT}/etc/mkinitcpio.conf.d/20-plymouth.conf"

# The ram disk is rebuilt either way, and a theme that could not be built is
# reported last rather than leaving a hook no image was built with. Split from
# `plymouth-set-default-theme -R`, which ends on exit 0 whatever happened.
themed=true
if chroot_aur_install plymouth-theme-arch-os; then
    arch-chroot "$MNT" plymouth-set-default-theme arch-os
else
    themed=false
fi
arch-chroot "$MNT" mkinitcpio -P
[ "$themed" = "true" ]

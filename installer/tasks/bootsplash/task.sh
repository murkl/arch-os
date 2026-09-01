# Show a logo while the system starts instead of a wall of kernel messages.

simulating && return 0

chroot_pacman_install plymouth git base-devel

# The hook goes directly behind whichever init hook is in use, which is early
# enough to have a screen to draw on. Matched that way rather than against the
# whole line, so it still lands when the rest of the list changes.
sed -i 's/^HOOKS=(\(base [a-z]*\)/HOOKS=(\1 plymouth/' "${MNT}/etc/mkinitcpio.conf"
if ! grep -qE '^HOOKS=\(.*\bplymouth\b' "${MNT}/etc/mkinitcpio.conf"; then
    echo "plymouth could not be added to the mkinitcpio hooks" >&2
    exit 1
fi

chroot_aur_install plymouth-theme-arch-os

# Split rather than done with `plymouth-set-default-theme -R`: that command ends
# on `exit 0` whatever mkinitcpio made of the rebuild.
arch-chroot "$MNT" plymouth-set-default-theme arch-os
arch-chroot "$MNT" mkinitcpio -P

# And what was built rather than what was asked for: plymouth's build hook says
# so and gives up when it cannot find the theme's plugin or font, and mkinitcpio
# finishes the image without it. That image boots perfectly well, without a
# splash.
for image in $(kernel_images); do
    if ! arch-chroot "$MNT" lsinitcpio "$image" | grep -q 'plymouthd'; then
        echo "plymouth is missing from ${image}" >&2
        exit 1
    fi
done

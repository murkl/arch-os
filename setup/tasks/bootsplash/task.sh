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

# The theme first, then the ram disk it goes into. Split rather than done in one
# go with `plymouth-set-default-theme -R`: that command ends on `exit 0`
# whatever mkinitcpio made of the rebuild, so an image that failed to build
# would leave this task looking like it worked and the machine booting without a
# splash.
arch-chroot "$MNT" plymouth-set-default-theme arch-os
arch-chroot "$MNT" mkinitcpio -P

# And what was built rather than what was asked for. plymouth's is a build hook
# like any other: when it cannot find the theme's plugin or its font it says so
# and gives up, and mkinitcpio finishes the image without it. That image boots
# perfectly well — it simply has no splash in it, which is the one outcome
# nobody would go looking for the cause of.
for image in $(kernel_images); do
    if ! arch-chroot "$MNT" lsinitcpio "$image" | grep -q 'plymouthd'; then
        echo "plymouth is missing from ${image}" >&2
        exit 1
    fi
done

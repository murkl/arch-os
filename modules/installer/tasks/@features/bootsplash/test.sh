# The theme, the daemon in the image the firmware starts, and a card driver to
# draw on - each has gone missing quietly before. See docs/REFERENCE.md.
grep -qx 'Theme=arch-os' "${MNT}/etc/plymouth/plymouthd.conf"
while read -r image; do
    contents="$(arch-chroot "$MNT" lsinitcpio "$image")"
    grep -q 'plymouthd' <<<"$contents"
    grep -q 'themes/arch-os/' <<<"$contents"
    grep -q 'gpu/drm/' <<<"$contents"
done < <(boot_images)

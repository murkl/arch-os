# Theme, plymouthd and a DRM driver in every image. Each can go missing without
# an error: docs/REFERENCE.md
grep -qx 'Theme=arch-os' "${MNT}/etc/plymouth/plymouthd.conf"
while read -r image; do
    contents="$(arch-chroot "$MNT" lsinitcpio "$image")"
    grep -q 'plymouthd' <<<"$contents"
    grep -q 'themes/arch-os/' <<<"$contents"
    grep -q 'gpu/drm/' <<<"$contents"
done < <(boot_images)

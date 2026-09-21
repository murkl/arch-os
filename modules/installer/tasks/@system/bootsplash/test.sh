# A splash is three things, and any one of them missing is a machine that comes
# up in plain text without saying so: the theme it was told to draw, the daemon
# inside the image the firmware starts, and a card driver for it to draw on.
# Each has failed quietly before - see docs/REFERENCE.md.
simulating && return 0

grep -qx 'Theme=arch-os' "${MNT}/etc/plymouth/plymouthd.conf"

while read -r image; do
    contents="$(arch-chroot "$MNT" lsinitcpio "$image")"
    grep -q 'plymouthd' <<<"$contents"
    grep -q 'themes/arch-os/' <<<"$contents"
    grep -q 'gpu/drm/' <<<"$contents"
done < <(boot_images)

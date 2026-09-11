# A splash is three things, and any one of them missing is a machine that comes
# up in plain text without ever saying so: the theme it was told to draw, the
# daemon inside the image the firmware starts, and something for that daemon to
# draw on.
#
# Each has failed quietly before. Plymouth's build hook gives up when it cannot
# find the theme's plugin or font and mkinitcpio finishes the image without it;
# and plymouth never draws on the firmware framebuffer - it only touches the
# simpledrm device when UseSimpledrm is set, which Arch does not set - so an
# image with no card driver in it waits out its device timeout and falls back to
# text, taking the passphrase prompt with it.
debugging && return 0

grep -qx 'Theme=arch-os' "${MNT}/etc/plymouth/plymouthd.conf"

while read -r image; do
    contents="$(arch-chroot "$MNT" lsinitcpio "$image")"
    grep -q 'plymouthd' <<<"$contents"
    grep -q 'themes/arch-os/' <<<"$contents"
    grep -q 'gpu/drm/' <<<"$contents"
done < <(boot_images)

# Both images the kernel is in, under whichever of the two names this system
# boots from - a check against the image this machine does not start from is a
# check of nothing. See boot_images.
debugging && return 0

while read -r image; do
    [ -f "${MNT}${image}" ]
done < <(boot_images)

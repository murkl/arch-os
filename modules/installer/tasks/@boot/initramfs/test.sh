# Both images the kernel is in, under whichever of the two names this system
# boots from - a check against the one it does not start from checks nothing.
simulating && return 0

while read -r image; do
    [ -f "${MNT}${image}" ]
done < <(boot_images)

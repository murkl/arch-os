# Read the device rather than trust that dd said nothing: a stick that reports a
# finished write and keeps none of it is the failure this is here for, and it is
# invisible until somebody tries to boot from it.
#
# The label is what the image carries and what the boot loader on it searches
# for, so a device answering with the image's own label is a device that holds
# that image.
debugging && return 0

label="$(blkid -o value -s LABEL "$(image)")"
[ -n "$label" ]

# The kernel may still be re-reading the table this write replaced.
for _ in $(seq 50); do
    [ "$(blkid -o value -s LABEL "$ARCH_OS_IMAGE_DEVICE")" = "$label" ] && return 0
    sleep 0.2
done

echo "${ARCH_OS_IMAGE_DEVICE} does not carry ${label} after writing" >&2
return 1

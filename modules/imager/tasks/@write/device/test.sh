# Read the device rather than trust that dd said nothing: a stick that reports a
# finished write and keeps none of it is invisible until somebody tries to boot
# from it. The label is what the image carries and what the boot loader on it
# searches for.
#
# lsblk rather than blkid, because lsblk reads what udev already recorded and
# needs no more rights than listing the disks did - a test that has to ask for a
# password is a test that hangs where nobody is typing.

label="$(blkid -o value -s LABEL "$(image)")"
[ -n "$label" ]

# The kernel may still be re-reading the table this write replaced. The device
# and its partitions are all asked: udev files the label of a hybrid image under
# the partition it lies in, and the disk itself carries none.
for _ in $(seq 50); do
    labels="$(lsblk -no LABEL "$ARCH_OS_IMAGE_DEVICE")"
    grep -qxF "$label" <<<"$labels" && return 0
    sleep 0.2
done

echo "${ARCH_OS_IMAGE_DEVICE} does not carry ${label} after writing" >&2
return 1

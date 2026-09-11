# The image, onto the device, as one raw copy. An Arch image is a hybrid ISO:
# it already carries the partition table and both boot paths a firmware looks
# for, so there is nothing to partition, format or install here - anything this
# did beyond copying would be undoing what the image was built as.

simulating && return 0

device="$ARCH_OS_IMAGE_DEVICE"
[ -b "$device" ] || {
    echo "${device} is not a block device" >&2
    exit 1
}

# A mounted partition would be written out from under its own file system, and
# the desktop that mounted it would go on writing its cache over the new image.
# umount -l is the fallback: a file manager still holding the stick open is the
# usual reason a plain umount refuses.
while read -r mountpoint; do
    [ -n "$mountpoint" ] || continue
    echo "unmounting ${mountpoint}"
    umount "$mountpoint" || umount -l "$mountpoint"
done < <(lsblk -nro MOUNTPOINT "$device")

if lsblk -nro MOUNTPOINT "$device" | grep -q .; then
    echo "${device} still has something mounted from it" >&2
    exit 1
fi

# oflag=sync rather than a sync afterwards: dd then reports progress the drive
# has actually taken, and a stick pulled out when the bar ends is a stick that
# was finished. The last sync is for the kernel's own caches.
dd if="$(image)" of="$device" bs=4M status=progress oflag=sync
sync

# The kernel is still holding the partition table the device had before this,
# so nothing reads the new one until it is told to look again.
partprobe "$device" 2>/dev/null || true

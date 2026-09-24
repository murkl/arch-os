# The image onto the device, as one raw copy. An Arch image is a hybrid ISO: it
# already carries the partition table and both boot paths a firmware looks for,
# so anything done here beyond copying would undo what the image was built as.
# https://wiki.archlinux.org/title/USB_flash_installation_medium
#
# Everything before the copy is a reason not to make it, and every one of those
# checks reads the machine as an ordinary user - nothing is escalated before
# there is a reason to.

# This module runs as whoever started it, on somebody's own machine, where a
# root process leaves two gigabytes in their home that only root can delete
# again. So the escalation lives in the one task that cannot do without it.
as_root() {
    if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

device="$ARCH_OS_IMAGE_DEVICE"
target="$(image)"

# /dev/sdb is a path, not a stick: by the next run an internal disk can be
# sitting at it. So the answer is checked against the same list it was chosen
# from, immediately before anything is written.
devices="$(list_devices | cut -f1)"
if ! grep -qxF "$device" <<<"$devices"; then
    echo "${device} is not a USB device on this machine. Plug the stick back in and choose it again." >&2
    exit 1
fi

# A device smaller than the image takes the first part of it and dd stops at the
# end. Caught here, because by then it has been overwritten for nothing.
have="$(lsblk -bdno SIZE "$device")"
need="$(stat -c %s "$target")"
if [ "$have" -lt "$need" ]; then
    echo "${device} holds $(numfmt --to=iec "$have") and the image needs $(numfmt --to=iec "$need")" >&2
    exit 1
fi

echo "Writing ${target##*/} to ${device}."
echo

# A mounted partition would be written out from under its own file system.
# umount -l is the fallback: a file manager still holding the stick open is
# the usual reason a plain umount refuses.
while read -r mountpoint; do
    [ -n "$mountpoint" ] || continue
    echo "Unmounting ${mountpoint}"
    as_root umount "$mountpoint" || as_root umount -l "$mountpoint"
done < <(lsblk -nro MOUNTPOINT "$device")

mounted="$(lsblk -nro MOUNTPOINT "$device")"
if grep -q . <<<"$mounted"; then
    echo "${device} still has something mounted from it" >&2
    exit 1
fi

# The flags the Wiki gives. oflag=direct bypasses the page cache, so the
# progress dd reports is what the drive has actually taken, and conv=fsync
# flushes the rest before dd returns - a stick pulled out when the bar ends
# is a stick that was finished.
as_root dd if="$target" of="$device" bs=4M status=progress conv=fsync oflag=direct

# Nothing reads the new partition table until the kernel is told to look.
# blockdev rather than partprobe: it is util-linux, which every Linux has, and
# parted, which partprobe comes with, is missing from many.
as_root blockdev --rereadpt "$device" 2>/dev/null || true

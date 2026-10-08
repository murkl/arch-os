# The image onto the device as one raw copy: a hybrid ISO already carries the
# partition table and both boot paths. Root only for the commands that need it,
# through as_root in oak.sh.
# https://wiki.archlinux.org/title/USB_flash_installation_medium

device="$ARCH_OS_IMAGE_DEVICE"
target="$(image)"

# By the next run an internal disk can sit at that path, so it is held to the
# list it was chosen from right before it is written.
devices="$(options_devices | cut -f1)"
if ! grep -qxF "$device" <<<"$devices"; then
    echo "${device} is not a USB device on this machine. Plug the stick back in and choose it again." >&2
    exit 1
fi

have="$(lsblk -bdno SIZE "$device")"
need="$(stat -c %s "$target")"
if [ "$have" -lt "$need" ]; then
    echo "${device} holds $(numfmt --to=iec "$have") and the image needs $(numfmt --to=iec "$need")" >&2
    exit 1
fi

echo "Writing ${target##*/} to ${device}."
echo

# A file manager still holding the stick open is why a plain umount refuses.
# Raw output writes a space in a stick's label as \x20.
while read -r mountpoint; do
    [ -n "$mountpoint" ] || continue
    mountpoint="$(printf '%b' "$mountpoint")"
    echo "Unmounting ${mountpoint}"
    as_root umount "$mountpoint" || as_root umount -l "$mountpoint"
done < <(lsblk -nro MOUNTPOINT "$device")

mounted="$(lsblk -nro MOUNTPOINT "$device")"
if grep -q . <<<"$mounted"; then
    echo "${device} still has something mounted from it" >&2
    exit 1
fi

# The Wiki's flags: oflag=direct makes the progress what the drive has taken,
# conv=fsync flushes the rest before dd returns.
as_root dd if="$target" of="$device" bs=4M status=progress conv=fsync oflag=direct

# blockdev rather than partprobe: util-linux is everywhere, parted is not.
as_root blockdev --rereadpt "$device" 2>/dev/null || true

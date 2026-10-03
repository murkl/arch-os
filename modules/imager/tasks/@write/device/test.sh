# The device read back, by the label the image carries and its boot loader
# searches for. lsblk rather than blkid: it needs no root, and a test that asks
# for a password hangs where nobody is typing.
label="$(blkid -o value -s LABEL "$(image)")"
[ -n "$label" ]

# The kernel may still be re-reading the table; the label lies on a partition.
for _ in $(seq 50); do
    labels="$(lsblk -no LABEL "$ARCH_OS_IMAGE_DEVICE")"
    grep -qxF "$label" <<<"$labels" && return 0
    sleep 0.2
done

echo "${ARCH_OS_IMAGE_DEVICE} does not carry ${label} after writing" >&2
return 1

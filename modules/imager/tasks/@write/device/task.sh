# The image, onto the device, as one raw copy. An Arch image is a hybrid ISO:
# it already carries the partition table and both boot paths a firmware looks
# for, so there is nothing to partition, format or install here - anything this
# did beyond copying would be undoing what the image was built as.
#
# Everything before the copy is a reason not to make it. This is the one step in
# the module that cannot be taken back, so what it checks, it checks first - and
# every one of those checks reads the machine as an ordinary user, so nothing is
# escalated before there is a reason to.

simulating && return 0

# This module runs as whoever started it, and that is the difference between it
# and the other two: they run on a booted live image, where everything is root
# already and there is no home to leave anything in. This one runs on somebody's
# own machine, where a root process leaves two gigabytes in their home that only
# root can delete again - and the program's own answers and log beside them.
#
# So the escalation lives here, in the one task that cannot do without it:
# writing a block device, unmounting what the desktop mounted, and making the
# kernel read the new partition table. Everything else this module does, the
# downloads included, is done as the person at the machine. Empty when that
# person is root already.
as_root() {
    if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

device="$ARCH_OS_IMAGE_DEVICE"
target="$(image)"

# The answer outlives the machine's view of its own disks: /dev/sdb is a path,
# not a stick, and by the next run the stick that answered to it can be gone and
# an internal disk sitting at that path. So the device is checked against the
# same list it was chosen from, immediately before anything is written.
if ! list_devices | cut -f1 | grep -qxF "$device"; then
    echo "${device} is not a USB device on this machine. Plug the stick back in and choose it again." >&2
    exit 1
fi

# A device smaller than the image takes the first part of it and dd stops at the
# end of it. Caught here rather than left to that error, because by then the
# device has been overwritten for nothing.
have="$(lsblk -bdno SIZE "$device")"
need="$(stat -c %s "$target")"
if [ "$have" -lt "$need" ]; then
    echo "${device} holds $(numfmt --to=iec "$have") and the image needs $(numfmt --to=iec "$need")" >&2
    exit 1
fi

# From here on the terminal itself, rather than this run's output: sudo draws
# its prompt on /dev/tty and reads what is typed from it, and dd reports its
# progress on stderr, which Oak collects into the log. Inherited, the password
# would be asked for where nobody can see it and a three minute write would look
# like a screen that stopped. `tty: true` in the yaml is what makes the terminal
# this script's to take.
{
    echo "Writing ${target##*/} to ${device}."
    echo

    # A mounted partition would be written out from under its own file system,
    # and the desktop that mounted it would go on writing its cache over the new
    # image. umount -l is the fallback: a file manager still holding the stick
    # open is the usual reason a plain umount refuses.
    while read -r mountpoint; do
        [ -n "$mountpoint" ] || continue
        echo "Unmounting ${mountpoint}"
        as_root umount "$mountpoint" || as_root umount -l "$mountpoint"
    done < <(lsblk -nro MOUNTPOINT "$device")

    if lsblk -nro MOUNTPOINT "$device" | grep -q .; then
        echo "${device} still has something mounted from it" >&2
        exit 1
    fi

    # oflag=sync rather than a sync afterwards: dd then reports progress the
    # drive has actually taken, and a stick pulled out when the bar ends is a
    # stick that was finished. The last sync is for the kernel's own caches and
    # needs nobody's permission.
    as_root dd if="$target" of="$device" bs=4M status=progress oflag=sync
    sync

    # The kernel is still holding the partition table the device had before
    # this, so nothing reads the new one until it is told to look again.
    as_root partprobe "$device" 2>/dev/null || true
} <>/dev/tty >&0 2>&0

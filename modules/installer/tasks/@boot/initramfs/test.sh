# Both images the kernel is in, under whichever of the two names this system
# boots from - a check against the one it does not start from checks nothing.

while read -r image; do
    [ -f "${MNT}${image}" ]

    # And an encrypted root can be opened from inside it, or the disk it is on
    # is a disk nobody gets into again.
    if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
        contents="$(arch-chroot "$MNT" lsinitcpio "$image")"
        grep -q 'usr/lib/systemd/systemd-cryptsetup$' <<<"$contents"
    fi
done < <(boot_images)

# Nothing is left mounted and, where there was one, the encrypted volume is
# locked again.

if mountpoint -q "$MNT"; then
    echo "${MNT} is still mounted" >&2
    exit 1
fi
[ "$ARCH_OS_RECOVERY_ENCRYPTED" != "true" ] || [ ! -e "/dev/mapper/${CRYPT}" ]

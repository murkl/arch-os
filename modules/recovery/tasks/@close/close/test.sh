# Nothing is left mounted and, where there was one, the encrypted volume is
# locked again.
debugging && return 0

! mountpoint -q "$MNT"
[ "$ARCH_OS_RECOVERY_ENCRYPTION_ENABLED" != "true" ] || [ ! -e "/dev/mapper/${CRYPT}" ]

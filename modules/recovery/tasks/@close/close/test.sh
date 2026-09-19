# Nothing is left mounted and, where there was one, the encrypted volume is
# locked again.
simulating && return 0

! mountpoint -q "$MNT"
[ "$ARCH_OS_RECOVERY_ENCRYPTED" != "true" ] || [ ! -e "/dev/mapper/${CRYPT}" ]

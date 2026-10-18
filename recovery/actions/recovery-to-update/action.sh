# On its own partition, or from anywhere else for a disk whose Recovery does
# not start, as an update cut short leaves it. A Recovery partition is the
# third, under the name the Installer gives it.
if on_recovery_partition; then
    return 0
fi
[ -n "$ARCH_OS_RECOVERY_DISK" ] || return 1
[ "$(lsblk -dno PARTLABEL "$(recovery_partition "$ARCH_OS_RECOVERY_DISK")" 2>/dev/null)" = recovery ] && ! recovery_starts

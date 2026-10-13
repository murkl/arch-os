# On its own partition, or from anywhere else for a disk whose Recovery does
# not start, as an update cut short leaves it.
if on_recovery_partition; then
    return 0
fi
has_recovery_partition && ! recovery_starts

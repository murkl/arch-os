# A snapshot before every package transaction, so an update that goes wrong can
# be rolled back from the boot menu.

simulating && return 0

if [ "$ARCH_OS_BTRFS_SNAPPER_ENABLED" = "true" ]; then
    # snapper's own hook: named snapshots, cleaned up on a timer.
    chroot_pacman_install snap-pac
    return 0
fi

# Without snapper there is still a file system that can snapshot, so it does —
# plainly, by date, and without anything cleaning up after it.
mkdir -p "${MNT}/etc/pacman.d/hooks"
{
    echo '[Trigger]'
    echo 'Operation = Install'
    echo 'Operation = Upgrade'
    echo 'Operation = Remove'
    echo 'Type = Package'
    echo 'Target = *'
    echo
    echo '[Action]'
    echo 'Description = Creating a snapshot before this transaction'
    echo 'When = PreTransaction'
    echo "Exec = /bin/sh -c '/usr/bin/btrfs subvolume snapshot -r / /.snapshots/\"\$(date \"+%Y-%m-%d_%H-%M-%S\")\"'"
} >"${MNT}/etc/pacman.d/hooks/50-btrfs-snapshot.hook"

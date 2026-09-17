# Without snapper the file system can still snapshot itself: one dated read-only
# snapshot per package transaction, and nothing cleaning up after it.

simulating && return 0

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

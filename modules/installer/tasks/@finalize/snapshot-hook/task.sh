# Without snapper there is still a file system that can snapshot itself, so a
# bad update can still be undone: one dated read-only snapshot per package
# transaction, and nothing cleaning up after it.
#
# Its own task beside the snapper one rather than a branch inside a shared one:
# the two are different answers to one question, and which of them runs is
# written in the yaml rather than read out of shell.

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

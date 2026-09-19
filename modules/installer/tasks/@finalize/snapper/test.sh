# There has to be somewhere for a snapshot to go, and a configuration snapper
# itself answers for - a directory alone is a snapshot nothing ever takes.
simulating && return 0

arch-chroot "$MNT" test -d /.snapshots

# And every setting has to be the one that was set. Read back out of snapper
# rather than out of its file, in the machine-readable shape it offers for it,
# and against module.sh rather than against numbers repeated here: set-config
# accepts a mangled value without a word, and the limits it then keeps are the
# package's - which is the disk filling up that these exist to prevent.
config="$(arch-chroot "$MNT" snapper --no-dbus --csvout --no-headers -c root get-config)"
while IFS= read -r setting; do
    grep -qxF "${setting/=/,}" <<<"$config"
done < <(snapper_config)

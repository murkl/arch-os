# The snapshot in place of @. The new @ is built before the old one is touched,
# so a rollback that dies halfway leaves the system as it was.
# https://wiki.archlinux.org/title/Btrfs#Restoring_a_snapshot

snapshot="$ARCH_OS_RECOVERY_SNAPSHOT"
if [ ! -d "${BTRFS_TOP}/${snapshot}" ]; then
    echo "There is no snapshot at ${snapshot}." >&2
    return 1
fi

# A subvolume made inside @, such as a machine or a container's image, is in no
# snapshot of it. Each moves from $1 to the same place in $2, where a snapshot
# holds an empty directory for it or nothing, and never through a link: one in
# a snapshot resolves on this live system. Every place is checked before the
# first move, so a refusal leaves both as they were.
carry_subvolumes() {
    local to="${BTRFS_TOP}/$2" paths path place
    paths="$(btrfs subvolume list -o "${BTRFS_TOP}/$1" | sed 's/^ID [0-9]* gen [0-9]* top level [0-9]* path //')"
    [ -n "$paths" ] || return 0
    while read -r path; do
        place="${to}/${path#*/}"
        if [ "$(realpath -m "$place")" != "$place" ]; then
            echo "/${path#*/} is a subvolume, and ${2} links that place elsewhere" >&2
            return 1
        fi
        if [ -e "$place" ] && [ -z "$(find "$place" -maxdepth 0 -type d -empty)" ]; then
            echo "/${path#*/} is a subvolume, and ${2} holds something else there" >&2
            return 1
        fi
    done <<<"$paths"
    while read -r path; do
        place="${to}/${path#*/}"
        [ ! -e "$place" ] || rmdir "$place"
        mkdir -p "$(dirname "$place")"
        mv -T "${BTRFS_TOP}/${path}" "$place"
        echo "carried the subvolume /${path#*/} over to ${2}"
    done <<<"$paths"
}

# The system being replaced, kept read-only under the next number as snapper
# rollback keeps it, so the rollback can be undone from the same list.
keep_replaced() {
    local dir number=0
    for dir in "${BTRFS_TOP}/@snapshots/"*/; do
        dir="$(basename "$dir")"
        if [[ $dir =~ ^[0-9]+$ ]] && [ "$dir" -gt "$number" ]; then
            number="$dir"
        fi
    done
    number=$((number + 1))
    mkdir "${BTRFS_TOP}/@snapshots/${number}"
    btrfs subvolume snapshot -r "${BTRFS_TOP}/@" "${BTRFS_TOP}/@snapshots/${number}/snapshot"
    render "$(where)/info.xml" NUMBER="$number" DATE="$(date -u '+%F %T')" >"${BTRFS_TOP}/@snapshots/${number}/info.xml"
    chmod 640 "${BTRFS_TOP}/@snapshots/${number}/info.xml"
    echo "kept the replaced system as snapshot ${number}"
}

# @ cannot be replaced while it is the mounted root.
unmount_target

# What an attempt cut short carried over goes back before its new @ goes.
if [ -e "${BTRFS_TOP}/@.new" ]; then
    carry_subvolumes @.new @
    btrfs subvolume delete --recursive "${BTRFS_TOP}/@.new"
fi
btrfs subvolume snapshot "${BTRFS_TOP}/${snapshot}" "${BTRFS_TOP}/@.new"

# The Secure Boot keys belong to the firmware, not to a point in time: a
# snapshot from before them could sign nothing it rebuilds.
if [ -d "${BTRFS_TOP}/@/var/lib/sbctl" ]; then
    rm -rf "${BTRFS_TOP}/@.new/var/lib/sbctl"
    cp -a "${BTRFS_TOP}/@/var/lib/sbctl" "${BTRFS_TOP}/@.new/var/lib/sbctl"
fi

keep_replaced
carry_subvolumes @ @.new
btrfs subvolume delete --recursive "${BTRFS_TOP}/@"
mv "${BTRFS_TOP}/@.new" "${BTRFS_TOP}/@"
mount_target

# The lock of the transaction that broke it would stop further repairs.
rm -f "${MNT}/var/lib/pacman/db.lck"

# On the disk before the run says so: btrfs commits a swap like this only on
# its next transaction.
sync
echo "@ is now ${snapshot}"

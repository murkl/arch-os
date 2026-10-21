# Each subvolume mounted where the layout says rather than only created: an
# unmounted one leaves a plain directory inside @ that every snapshot carries.
mountpoint -q "$MNT"
mountpoint -q "${MNT}/boot"

# One signature on the system partition: one left from what the disk held
# before is ambivalent to blkid, and mount may read that one instead.
blkid -p "$(system_partition "$ARCH_OS_DISK")" >/dev/null

# Encrypted, the system goes onto the opened volume, not the partition under it.
if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
    system_part="$(system_partition "$ARCH_OS_DISK")"
    root_source="$(findmnt -no SOURCE "$MNT")"
    [[ $root_source == /dev/mapper/cryptroot* ]]
    [ "$(cryptsetup status cryptroot | awk '$1 == "device:" { print $2 }')" = "$system_part" ]
    flags="$(cryptsetup luksDump "$system_part" | sed -n 's/^Flags:[[:space:]]*//p')"
    grep -qw allow-discards <<<"$flags"
    if [ "$(lsblk -dnro ROTA "$ARCH_OS_DISK")" = "0" ]; then
        grep -qw no-read-workqueue <<<"$flags"
        grep -qw no-write-workqueue <<<"$flags"
    fi
fi

while IFS=$'\t' read -r subvolume path; do
    findmnt -no OPTIONS "${MNT}${path%/}" | grep -qE "(^|,)subvol=/${subvolume}(,|$)"
done < <(btrfs_subvolumes)

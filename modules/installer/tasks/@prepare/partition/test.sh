# Each subvolume mounted where the layout says rather than only created: an
# unmounted one leaves a plain directory inside @ that every snapshot carries.
mountpoint -q "$MNT"
mountpoint -q "${MNT}/boot"

# Encrypted, the system goes onto the opened volume, not the partition under it.
if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
    root_source="$(findmnt -no SOURCE "$MNT")"
    [[ $root_source == /dev/mapper/cryptroot* ]]
    [ "$(cryptsetup status cryptroot | awk '$1 == "device:" { print $2 }')" = "$ROOT_PART" ]
    cryptsetup luksDump "$ROOT_PART" | grep -qE '^Flags:.*allow-discards'
fi

while IFS=$'\t' read -r subvolume path; do
    findmnt -no OPTIONS "${MNT}${path%/}" | grep -qE "(^|,)subvol=/${subvolume}(,|$)"
done < <(btrfs_subvolumes)

[[ $(lsattr -d "${MNT}/var/lib/libvirt/images" | awk '{ print $1 }') == *C* ]]

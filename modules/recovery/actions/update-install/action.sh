# The newer Recovery over this one. Everything that can fail is done before the
# partition is touched: the download held to its checksum, its size to the
# partition, and with Secure Boot on the boot image signed with the system's
# own keys, which only the opened system holds. Then the partition, read back,
# and the boot image moved over the old one, so the two disagree only for the
# length of the write.

tar=/tmp/arch-os-recovery-update.tar

# Where the EFI partition is mounted while the Recovery is updated without the
# system.
esp_mnt=/run/arch-os-esp

check_online || exit "$EXIT_OFFLINE"
json="$(release_json latest)" || exit "$EXIT_UNREACHABLE"
found="$(newer_recovery <<<"$json")"
if [ -z "$found" ]; then
    echo "there is no newer Recovery to install" >&2
    exit 1
fi
read -r version url digest <<<"$found"

echo "fetching ${url##*/}"
if ! fetch_url --progress-bar --retry 3 --retry-delay 2 "$url" -o "${tar}.part"; then
    rm -f "${tar}.part"
    check_online || exit "$EXIT_OFFLINE"
    echo "downloading ${url##*/} failed" >&2
    exit 10
fi
if ! echo "${digest}  ${tar}.part" | sha256sum -c - >/dev/null; then
    rm -f "${tar}.part"
    echo "${url##*/} does not match the checksum its release publishes and was thrown away" >&2
    exit 11
fi
mv -f "${tar}.part" "$tar"

stem="arch-os-${version}-recovery"
part="$(recovery_partition "$ARCH_OS_RECOVERY_DISK")"
size="$(tar -tvf "$tar" "${stem}/recovery.img" | awk '{ print $3 }')"
room="$(blockdev --getsize64 "$part")"
if [ -z "$size" ] || [ "$size" -gt "$room" ]; then
    echo "the Recovery ${version} takes ${size:-?} bytes, and its partition ${part} holds ${room}" >&2
    exit 12
fi

# The system's own EFI partition, through the opened system where it signs.
# What an earlier attempt left mounted goes first.
close_target
if mountpoint -q "$esp_mnt"; then
    umount "$esp_mnt"
fi
if [ "$ARCH_OS_RECOVERY_SECURE_BOOT" = "true" ]; then
    if [ "$ARCH_OS_RECOVERY_ENCRYPTED" = "true" ]; then
        printf '%s' "$ARCH_OS_RECOVERY_KEYS_PASSWORD" | cryptsetup open "$(target_partition)" "$CRYPT"
    fi
    mount_target
    esp="${MNT}/boot"
else
    mount --mkdir -t vfat "$(boot_partition "$ARCH_OS_RECOVERY_DISK")" "$esp_mnt"
    esp="$esp_mnt"
fi
efi="${esp}/EFI/Linux/$(basename "$RECOVERY_EFI")"
tar -xOf "$tar" "${stem}/recovery.efi" >"${efi}.new"
if [ "$ARCH_OS_RECOVERY_SECURE_BOOT" = "true" ]; then
    arch-chroot "$MNT" sbctl sign -o "${RECOVERY_EFI}.signed" "${RECOVERY_EFI}.new"
    mv -f "${efi}.signed" "${efi}.new"
fi

echo "writing the Recovery ${version} to ${part}"
if ! tar -xOf "$tar" "${stem}/recovery.img" | dd of="$part" bs=4M conv=fsync status=none; then
    echo "writing ${part} failed" >&2
    exit 13
fi
want="$(tar -xOf "$tar" "${stem}/recovery.img" | sha256sum)"
have="$(head -c "$size" "$part" | sha256sum)"
if [ "$have" != "$want" ]; then
    echo "${part} does not read back as the Recovery ${version}" >&2
    exit 13
fi
mv -f "${efi}.new" "$efi"
sync
if [ "$esp" = "$esp_mnt" ]; then
    umount "$esp_mnt"
fi
close_target
rm -f "$tar"
echo "the Recovery is now ${version}"

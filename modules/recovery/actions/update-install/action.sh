# The Recovery recovery_update finds, over the one on the disk. Everything that
# can fail comes before the partition is touched: the download held to its
# checksum, its size to the partition, and where the system signs its boot
# chain the boot image signed with the system's own keys. Then the partition,
# read back off the disk, and the boot image moved over the old one, so the two
# disagree only for the length of the write.

tar=/tmp/arch-os-recovery-update.tar

# Where the EFI partition is mounted while the system stays closed.
esp_mnt=/run/arch-os-esp

check_online || exit "$EXIT_OFFLINE"
json="$(release_json)" || exit "$EXIT_UNREACHABLE"
found="$(recovery_update <<<"$json")"
if [ -z "$found" ]; then
    echo "there is no Recovery to install" >&2
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

# What an earlier attempt left open or mounted goes first. Arch OS signs its
# boot chain only behind encryption, so an encrypted system is opened, and its
# EFI partition is reached through it.
close_target
if mountpoint -q "$esp_mnt"; then
    umount "$esp_mnt"
fi
if [ "$ARCH_OS_RECOVERY_ENCRYPTED" = "true" ]; then
    printf '%s' "$ARCH_OS_RECOVERY_UPDATE_PASSWORD" | cryptsetup open "$(target_partition)" "$CRYPT"
    mount_target
    esp="${MNT}/boot"
else
    mount --mkdir -t vfat "$(boot_partition "$ARCH_OS_RECOVERY_DISK")" "$esp_mnt"
    esp="$esp_mnt"
fi

# A copy an attempt cut short left takes room the kernel images need, so it
# goes first, and this one goes again if anything below fails.
efi="${esp}${RECOVERY_EFI#/boot}"
rm -f "${efi}.new"
trap 'rm -f "${efi}.new"' EXIT
tar -xOf "$tar" "${stem}/recovery.efi" >"${efi}.new"

# Signed where the system has sbctl, as the boot files are rebuilt.
if [ "$esp" != "$esp_mnt" ] && [ -x "${MNT}/usr/bin/sbctl" ]; then
    arch-chroot "$MNT" sbctl sign "${RECOVERY_EFI}.new"
fi

echo "writing the Recovery ${version} to ${part}"
if ! tar -xOf "$tar" "${stem}/recovery.img" | dd of="$part" bs=4M conv=fsync status=none; then
    echo "writing ${part} failed" >&2
    exit 13
fi

# Read off the disk rather than out of the memory the write went through.
blockdev --flushbufs "$part"
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

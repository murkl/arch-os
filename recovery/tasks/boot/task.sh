# Restores each kernel image from its module folder, where Arch installs it,
# then rebuilds everything booted from it.

# UKIs where the system's preset builds them, initramfs images otherwise.
kind=image
grep -qs '^default_uki=' "${MNT}/etc/mkinitcpio.d/${KERNEL}.preset" && kind=uki

# The command line from the existing entries, whatever their try count, the
# fallback's where the main one is lost. A UKI carries its own.
cmdline=""
if [ "$kind" = image ]; then
    for entry in "${MNT}/boot/loader/entries/main.conf" "${MNT}/boot/loader/entries/main+"*.conf \
        "${MNT}/boot/loader/entries/main-fallback.conf" "${MNT}/boot/loader/entries/main-fallback+"*.conf; do
        [ -e "$entry" ] || continue
        cmdline="$(awk '!found && sub(/^options[[:space:]]+/, "") { print; found = 1 }' "$entry")"
        [ -z "$cmdline" ] || break
    done
    # The Installer's record in the system, where the entries are lost.
    if [ -z "$cmdline" ] && [ -s "${MNT}/etc/kernel/cmdline" ]; then
        cmdline="$(<"${MNT}/etc/kernel/cmdline")"
    fi
    if [ -z "$cmdline" ]; then
        echo "no boot entry of the system has an options line" >&2
        exit 1
    fi
fi

# The Installer's layout, with entries that fall back to the Recovery. The
# preset first, since the kernels and mkinitcpio follow where it says.
boot_preset "$MNT" "$kind"
restore_kernels "$MNT"
[ "$kind" = image ] || mkdir -p "${MNT}${UKI_DIR}"
arch-chroot "$MNT" mkinitcpio -P

# Secure Boot refuses a rebuilt UKI until it is signed. A moved one is signed
# at its new path before an entry points at it.
if [ -x "${MNT}/usr/bin/sbctl" ]; then
    if [ "$kind" = uki ]; then
        while read -r image; do
            arch-chroot "$MNT" sbctl sign -s "$image"
        done < <(images_of uki)
    fi
    arch-chroot "$MNT" sbctl sign-all || echo "signing the boot chain failed. Enroll or sign by hand before turning Secure Boot back on." >&2
fi

# The loader too, which a full partition or a cleaning firmware may remove.
# Installed from the live system as the Installer does, signed at its source by
# sbctl. A firmware refusing its entry still starts the fallback path, which
# test.sh checks.
bootctl --root="$MNT" --esp-path=/boot --variables=yes --graceful install

boot_entries "$MNT" "$kind" "$cmdline"

# UKIs in EFI/Linux go, since the loader lists them there beside the counted
# entries.
signed="$([ ! -x "${MNT}/usr/bin/sbctl" ] || arch-chroot "$MNT" sbctl list-files --json)"
for old in "/boot/EFI/Linux/arch-${KERNEL}.efi" "/boot/EFI/Linux/arch-${KERNEL}-fallback.efi"; do
    if grep -qF "\"${old}\"" <<<"$signed"; then
        arch-chroot "$MNT" sbctl remove-file "$old"
    fi
    if [ -e "${MNT}${old}" ]; then
        rm -f "${MNT}${old}"
        echo "removed ${old}, which the entries replace"
    fi
done

clear_loader_default

# On disk before reporting: on the FAT EFI partition, a power cut leaves
# unwritten files empty.
sync
echo "boot rebuilt"

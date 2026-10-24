# Each kernel image put back beside its modules, out of the folder the snapshot
# restored them with: Arch installs the image there and copies it to /boot. Then
# everything booted from it rebuilt.

# A module folder without a kernel in it is what an interrupted removal leaves.
# Each image goes under the name its package gives it in pkgbase, as mkinitcpio's
# pacman hook copies it, so a second kernel never lands under linux-zen's.
for dir in "${MNT}/usr/lib/modules/"*/; do
    [ -e "${dir}kernel" ] || continue
    version="$(basename "$dir")"
    if [ ! -f "${dir}vmlinuz" ] || [ ! -s "${dir}pkgbase" ]; then
        echo "There is no kernel image beside the modules of ${version}." >&2
        exit 10
    fi
    # Moved over the old image only once it is whole.
    name="vmlinuz-$(<"${dir}pkgbase")"
    image="${MNT}/boot/${name}"
    cp "${dir}vmlinuz" "${image}.new"
    mv -f "${image}.new" "$image"
    echo "restored ${name} from the modules of ${version}"
done

# Unified images where the system's preset builds them, ram disks otherwise.
kind=image
grep -qs '^default_uki=' "${MNT}/etc/mkinitcpio.d/${KERNEL}.preset" && kind=uki

# The command line a ram disk's entry starts it with, read off the entry it
# has, under whatever count it carries. A unified image carries its own.
cmdline=""
if [ "$kind" = image ]; then
    for entry in "${MNT}/boot/loader/entries/main.conf" "${MNT}/boot/loader/entries/main+"*.conf; do
        [ -e "$entry" ] || continue
        cmdline="$(awk '!found && sub(/^options[[:space:]]+/, "") { print; found = 1 }' "$entry")"
        [ -z "$cmdline" ] || break
    done
    if [ -z "$cmdline" ]; then
        echo "no boot entry of the system names the command line it starts with" >&2
        exit 1
    fi
fi

# The layout the Installer lays down, with the entries that fall back to the
# Recovery: the preset first, since mkinitcpio builds where it says.
boot_preset "$MNT" "$kind"
[ "$kind" = image ] || mkdir -p "${MNT}${UKI_DIR}"
arch-chroot "$MNT" mkinitcpio -P

# A rebuilt unified image is unsigned, and Secure Boot refuses it. One that
# moved is signed where it is now before an entry points at it.
if [ -x "${MNT}/usr/bin/sbctl" ]; then
    if [ "$kind" = uki ]; then
        while read -r image; do
            arch-chroot "$MNT" sbctl sign -s "$image"
        done < <(images_of uki)
    fi
    arch-chroot "$MNT" sbctl sign-all || echo "signing the boot chain again failed: enroll or sign by hand before switching Secure Boot back on" >&2
fi

# The loader too, which a full partition or a firmware that cleans up may have
# taken. From out here, as the Installer puts it there, and signed where sbctl
# signed it at its source. A firmware that refuses its entry still starts the
# fallback path, which test.sh holds to the loader.
bootctl --root="$MNT" --esp-path=/boot --variables=yes --graceful install

boot_entries "$MNT" "$kind" "$cmdline"

# Unified images in EFI/Linux: the loader lists them on its own there, beside
# the entries that count.
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

# On the disk before the run says so: the EFI partition is FAT, and a power cut
# leaves what was still in memory as empty files.
sync
echo "boot rebuilt"

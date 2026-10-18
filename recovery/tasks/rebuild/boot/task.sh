# Each kernel image put back beside the modules restored with the snapshot,
# from the system's own package cache, and everything booted from it rebuilt.
# Read with the system's own bsdtar, which reads whatever its pacman fetched.

cache=/var/cache/pacman/pkg

# The cached package that holds the image of a module directory, asked of each
# package rather than read off its name: 6.16.1 and 6.16.12, or two releases of
# one version, share every prefix. The signatures beside them are left out.
kernel_cached() {
    local package found=""
    while read -r package; do
        [ -z "$found" ] || continue
        if arch-chroot "$MNT" bsdtar -tf "${cache}/${package}" "usr/lib/modules/${1}/vmlinuz" >/dev/null 2>&1; then
            found="$package"
        fi
    done < <({ find "${MNT}${cache}" -maxdepth 1 -name "${KERNEL}-[0-9]*.pkg.tar.*" ! -name '*.sig' -printf '%f\n' 2>/dev/null || true; } | sort -rV)
    printf '%s' "$found"
}

# A module folder without a kernel in it is what an interrupted removal leaves.
for dir in "${MNT}/usr/lib/modules/"*/; do
    [ -e "${dir}kernel" ] || continue
    version="$(basename "$dir")"
    package="$(kernel_cached "$version")"
    if [ -z "$package" ]; then
        echo "There is no ${KERNEL} package for ${version} in the package cache." >&2
        exit 10
    fi
    # Moved over the old image only once it is whole.
    image="${MNT}/boot/vmlinuz-${KERNEL}"
    arch-chroot "$MNT" bsdtar -xOf "${cache}/${package}" "usr/lib/modules/${version}/vmlinuz" >"${image}.new"
    mv -f "${image}.new" "$image"
    echo "restored vmlinuz-${KERNEL} from ${package}"
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

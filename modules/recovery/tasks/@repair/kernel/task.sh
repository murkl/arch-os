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
        return 1
    fi
    # Moved over the old image only once it is whole.
    image="${MNT}/boot/vmlinuz-${KERNEL}"
    arch-chroot "$MNT" bsdtar -xOf "${cache}/${package}" "usr/lib/modules/${version}/vmlinuz" >"${image}.new"
    mv -f "${image}.new" "$image"
    echo "restored vmlinuz-${KERNEL} from ${package}"
done

# The presets know whether this system boots a ram disk or a unified image.
arch-chroot "$MNT" mkinitcpio -P

# A rebuilt unified image is unsigned, and Secure Boot refuses it.
if [ -x "${MNT}/usr/bin/sbctl" ]; then
    arch-chroot "$MNT" sbctl sign-all || echo "signing the boot chain again failed - enroll or sign by hand before switching Secure Boot back on" >&2
fi

echo "boot rebuilt"

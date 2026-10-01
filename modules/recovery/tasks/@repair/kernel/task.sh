# Each kernel image put back beside the modules restored with the snapshot,
# from the system's own package cache, and everything booted from it rebuilt.

# The newest cached package for a module directory. What stands before its first
# hyphen is the version, followed by a dot or a hyphen, or 6.16.1 would take
# 6.16.12's image. The signatures beside them are left out.
kernel_cached() {
    { find "${MNT}/var/cache/pacman/pkg" -maxdepth 1 \
        -name "${KERNEL}-${1%%-*}[.-]*.pkg.tar.*" ! -name '*.sig' 2>/dev/null || true; } |
        sort -V | tail -n1
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
    bsdtar -xOf "$package" "usr/lib/modules/${version}/vmlinuz" >"${MNT}/boot/vmlinuz-${KERNEL}"
    echo "restored vmlinuz-${KERNEL} from $(basename "$package")"
done

# The presets know whether this system boots a ram disk or a unified image.
arch-chroot "$MNT" mkinitcpio -P

# A rebuilt unified image is unsigned, and Secure Boot refuses it.
if [ -x "${MNT}/usr/bin/sbctl" ]; then
    arch-chroot "$MNT" sbctl sign-all || echo "signing the boot chain again failed - enroll or sign by hand before switching Secure Boot back on" >&2
fi

echo "boot rebuilt"

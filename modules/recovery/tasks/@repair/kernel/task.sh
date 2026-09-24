# The kernel images put back beside the modules that were restored with the
# snapshot, and everything that boots from them rebuilt.
#
# Needed after a rollback that went back past a kernel update: the modules under
# the restored root and the image in /boot are then two different kernels, and
# the machine comes up without a single module. Everything is taken from the
# system's own package cache rather than off a network it may not have.

# The newest cached package of the kernel for a module directory, or nothing. A
# module directory is named after the package version with the release joined
# on, so what stands before the first hyphen is what the file name carries -
# followed by the dot or the hyphen that ends it, or modules of 6.16.1 would
# take the image of 6.16.12 from the same cache. The signature beside each
# package matches the same pattern and sorts after it, so it is excluded.
kernel_cached() {
    { find "${MNT}/var/cache/pacman/pkg" -maxdepth 1 \
        -name "${KERNEL}-${1%%-*}[.-]*.pkg.tar.*" ! -name '*.sig' 2>/dev/null || true; } |
        sort -V | tail -n1
}

while read -r version; do
    package="$(kernel_cached "$version")"
    if [ -z "$package" ]; then
        echo "There is no ${KERNEL} package for ${version} in the package cache." >&2
        return 1
    fi
    bsdtar -xOf "$package" "usr/lib/modules/${version}/vmlinuz" >"${MNT}/boot/vmlinuz-${KERNEL}"
    echo "restored vmlinuz-${KERNEL} from $(basename "$package")"
done < <(installed_kernels)

# The presets are the one place that knows whether this system boots a plain ram
# disk or a signed unified image.
arch-chroot "$MNT" mkinitcpio -P

# A rebuilt unified image is an unsigned one, and a machine with Secure Boot on
# refuses to start it. sbctl's own database says what this system signs.
if [ -x "${MNT}/usr/bin/sbctl" ]; then
    arch-chroot "$MNT" sbctl sign-all || echo "signing the boot chain again failed - enroll or sign by hand before switching Secure Boot back on" >&2
fi

echo "boot rebuilt"

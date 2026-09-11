# Put the kernel images back beside the modules that were restored with the
# snapshot, and rebuild everything that boots from them.
#
# Needed after a rollback that went back past a kernel update: the modules under
# the restored root and the image in /boot are then two different kernels, and
# the machine comes up without a single module.
#
# Everything is taken from the system's own package cache rather than off the
# network, which a machine being recovered may not have.

simulating && return 0

# The newest cached package for a kernel, or nothing. A module directory is named
# after the package version with the release joined on, so what stands before the
# first hyphen is what the file name carries.
#
# The signature beside each package is excluded outright: it ends in .pkg.tar.zst
# .sig, so it matches the same pattern and sorts after the package it belongs to
# - and the newest match was then a file bsdtar cannot read at all.
kernel_cached() {
    { find "${MNT}/var/cache/pacman/pkg" -maxdepth 1 \
        -name "${1}-${2%%-*}*.pkg.tar.*" ! -name '*.sig' 2>/dev/null || true; } |
        sort -V | tail -n1
}

while read -r version; do
    kind="$(kernel_package "$version")"
    package="$(kernel_cached "$kind" "$version")"
    if [ -z "$package" ]; then
        echo "There is no ${kind} package for ${version} in the package cache." >&2
        return 1
    fi
    bsdtar -xOf "$package" "usr/lib/modules/${version}/vmlinuz" >"${MNT}/boot/vmlinuz-${kind}"
    echo "restored vmlinuz-${kind} from $(basename "$package")"
done < <(installed_kernels)

# The presets are the one place that knows whether this system boots a plain ram
# disk or a signed unified image.
arch-chroot "$MNT" mkinitcpio -P

# A rebuilt unified image is an unsigned one, and a machine with Secure Boot on
# refuses to start it. sbctl's own database says what this system signs, so
# signing it all again is the whole repair, and a system that never had Secure
# Boot has no sbctl to run.
if [ -x "${MNT}/usr/bin/sbctl" ]; then
    arch-chroot "$MNT" sbctl sign-all || echo "signing the boot chain again failed - enroll or sign by hand before switching Secure Boot back on" >&2
fi

# GRUB lists the snapshots it can boot from the file system, so its menu is stale
# the moment @ changes. systemd-boot has nothing to regenerate.
[ -f "${MNT}/boot/grub/grub.cfg" ] && arch-chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg

echo "boot rebuilt"

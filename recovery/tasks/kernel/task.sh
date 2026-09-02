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

# Which package a module directory belongs to: 6.12.4-arch1-1 is the stock
# kernel, anything carrying zen, lts or hardened is that one.
kernel_package() {
    case "$1" in
    *zen*) echo linux-zen ;;
    *lts*) echo linux-lts ;;
    *hardened*) echo linux-hardened ;;
    *) echo linux ;;
    esac
}

# The newest cached package for a kernel, or nothing. A module directory is named
# after the package version with the release joined on, so what stands before the
# first hyphen is what the file name carries.
kernel_cached() {
    { find "${MNT}/var/cache/pacman/pkg" -maxdepth 1 -name "${1}-${2%%-*}*.pkg.tar.*" 2>/dev/null || true; } |
        sort -V | tail -n1
}

for dir in "${MNT}/usr/lib/modules/"*/; do
    # A leftover folder with no modules in it is not a kernel.
    [ -e "${dir}kernel" ] || continue
    version="$(basename "$dir")"
    kind="$(kernel_package "$version")"
    package="$(kernel_cached "$kind" "$version")"
    if [ -z "$package" ]; then
        echo "There is no ${kind} package for ${version} in the package cache." >&2
        return 1
    fi
    bsdtar -xOf "$package" "usr/lib/modules/${version}/vmlinuz" >"${MNT}/boot/vmlinuz-${kind}"
    echo "restored vmlinuz-${kind} from $(basename "$package")"
done

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

# The pairing this repair exists for: every kernel whose modules are in the
# restored system has its own image back beside them, and something built from
# that image to boot. A vmlinuz from one kernel next to the modules of another
# is a machine that comes up without a single module, which is the failure this
# task is here to undo - and it is invisible until that machine is restarted.
debugging && return 0

while read -r version; do
    kind="$(kernel_package "$version")"
    [ -f "${MNT}/boot/vmlinuz-${kind}" ]
    # A plain ram disk, or the signed unified image that replaces it where the
    # boot chain is signed. The presets decide which, so both are allowed.
    [ -f "${MNT}/boot/initramfs-${kind}.img" ] ||
        [ -f "${MNT}/boot/EFI/Linux/arch-${kind}.efi" ]
done < <(installed_kernels)

# The pairing this repair exists for: every kernel whose modules are in the
# restored system has its own image back beside them, and something built from
# that image to boot. A vmlinuz from one kernel next to the modules of another
# is a machine that comes up without a single module, and it is invisible until
# that machine is restarted.

while read -r version; do
    kind="$(kernel_package "$version")"
    # The image says which kernel it is in its own header, so the pairing is
    # read off the file rather than off the name it was put back under.
    file -b "${MNT}/boot/vmlinuz-${kind}" | grep -qF "version ${version} "
    # A plain ram disk, or the signed unified image that replaces it where the
    # boot chain is signed. The presets decide which, so both are allowed.
    [ -f "${MNT}/boot/initramfs-${kind}.img" ] ||
        [ -f "${MNT}/boot/EFI/Linux/arch-${kind}.efi" ]
done < <(installed_kernels)

# And where the boot chain is signed, everything rebuilt is signed again: the
# firmware refuses an unsigned image the moment Secure Boot is on.
[ ! -x "${MNT}/usr/bin/sbctl" ] || boot_chain_signed "$MNT"

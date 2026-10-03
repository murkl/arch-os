# Each kernel's own image beside its modules, read off the image's header rather
# than the name it was put back under, and something built from it to boot.
for dir in "${MNT}/usr/lib/modules/"*/; do
    [ -e "${dir}kernel" ] || continue
    file -b "${MNT}/boot/vmlinuz-${KERNEL}" | grep -qF "version $(basename "$dir") "
    [ -f "${MNT}/boot/initramfs-${KERNEL}.img" ] || [ -f "${MNT}/boot/EFI/Linux/arch-${KERNEL}.efi" ]
done

# Signed again where the chain is signed.
[ ! -x "${MNT}/usr/bin/sbctl" ] || boot_chain_signed "$MNT"

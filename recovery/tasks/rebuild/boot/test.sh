# Each kernel's own image beside its modules, read off the image's header rather
# than the name it was put back under, and something built from it to boot.
for dir in "${MNT}/usr/lib/modules/"*/; do
    [ -e "${dir}kernel" ] || continue
    file -b "${MNT}/boot/vmlinuz-${KERNEL}" | grep -qF "version $(basename "$dir") "
done

# Both images where the preset builds them, the entries that count their tries
# pointing at them, and no image left where the loader would list it twice.
kind=image
grep -qs '^default_uki=' "${MNT}/etc/mkinitcpio.d/${KERNEL}.preset" && kind=uki
while read -r image; do
    [ -f "${MNT}${image}" ]
done < <(images_of "$kind")
[ -f "${MNT}/boot/loader/entries/main+${BOOT_TRIES}.conf" ]
[ -f "${MNT}/boot/loader/entries/main-fallback+${BOOT_TRIES}.conf" ]
if grep -q '^default' "${MNT}/boot/loader/loader.conf"; then
    echo "loader.conf names a default, which is started however often it fails" >&2
    exit 1
fi
if compgen -G "${MNT}/boot/EFI/Linux/arch-${KERNEL}*.efi" >/dev/null; then
    echo "a unified image is still in EFI/Linux, where the loader lists it beside the entries" >&2
    exit 1
fi
arch-chroot "$MNT" systemctl is-enabled arch-os-boot-tries.service >/dev/null

# Signed again where the chain is signed.
[ ! -x "${MNT}/usr/bin/sbctl" ] || boot_chain_signed "$MNT"

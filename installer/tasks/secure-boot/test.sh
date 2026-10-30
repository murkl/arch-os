# Signing is never fatal, so this catches an unsigned chain before Secure Boot
# is switched on.
boot_chain_signed "$MNT"

# sbctl keeps fwupd's updater signed.
updater=/usr/lib/fwupd/efi/fwupdx64.efi
if [ -f "${MNT}${updater}" ]; then
    signed="$(arch-chroot "$MNT" sbctl list-files --json)"
    grep -qF "\"${updater}.signed\"" <<<"$signed"
fi

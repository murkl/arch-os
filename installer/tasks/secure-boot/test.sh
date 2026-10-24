# Signing is never fatal, so an unsigned chain is said here rather than found
# the day Secure Boot is switched on.
boot_chain_signed "$MNT"

# fwupd's updater among what sbctl keeps signed, where fwupd is installed.
updater=/usr/lib/fwupd/efi/fwupdx64.efi
if [ -f "${MNT}${updater}" ]; then
    arch-chroot "$MNT" sbctl list-files --json | grep -qF "\"${updater}.signed\""
fi

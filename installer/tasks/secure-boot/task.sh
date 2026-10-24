# Never fatal: a machine without Secure Boot still boots.
# docs/REFERENCE.md#secure-boot
# https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot

# -s makes sbctl's hook sign the Recovery again on every update. It records no
# file signed already (sbctl 0.18, Sign in sbctl.go), so the boot images rely on
# sbctl's mkinitcpio hook.
if [ -f "${MNT}${RECOVERY_EFI}" ]; then
    arch-chroot "$MNT" sbctl sign -s "$RECOVERY_EFI" || echo "signing the Recovery failed" >&2
fi

# Signed under the .signed name fwupd prefers. Arch ships no shim, so fwupd is
# told to boot without it, and --json drops the progress but keeps the error.
# https://github.com/fwupd/fwupd/blob/main/plugins/uefi-capsule/README.md
updater=/usr/lib/fwupd/efi/fwupdx64.efi
if [ -f "${MNT}${updater}" ]; then
    arch-chroot "$MNT" sbctl sign -s -o "${updater}.signed" "$updater" || echo "signing fwupd's updater failed" >&2
    arch-chroot "$MNT" fwupdtool --json modify-config uefi_capsule DisableShimForSecureBoot true ||
        echo "fwupd still looks for shim, firmware updates need Secure Boot off" >&2
fi

# Enrolling needs setup mode. In the UEFI variable four attribute bytes precede
# the value.
setup_mode=/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c
if [ ! -r "$setup_mode" ] || [ "$(od -An -t u1 -j 4 -N 1 "$setup_mode" 2>/dev/null | tr -d ' ')" != "1" ]; then
    echo "Secure Boot: firmware not in setup mode, keys not enrolled. The boot chain is signed, enrolling later is enough"
    return 0
fi
# Enrolled keys refuse whatever is unsigned, possibly at once.
if ! boot_chain_signed "$MNT"; then
    echo "Secure Boot: keys not enrolled, the boot chain is not fully signed" >&2
    return 0
fi
# -m keeps Microsoft's certificates, -f the firmware's own, which firmware signed
# by its maker needs. sbctl refuses -f where the firmware's defaults could be
# tampered with, so -m alone follows.
if arch-chroot "$MNT" sbctl enroll-keys -m -f || arch-chroot "$MNT" sbctl enroll-keys -m; then
    echo "Secure Boot: keys enrolled, switch Secure Boot on in the firmware settings"
else
    echo "Secure Boot: enrolling the keys failed" >&2
fi

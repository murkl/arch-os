# The Recovery signed with this machine's own keys, which the loader task made
# and signed systemd-boot and the boot images with, then the keys enrolled.
# Never fatal: a machine without Secure Boot boots perfectly well.
# docs/REFERENCE.md#secure-boot
# https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot

# The Recovery starts from the same menu, so it carries the same keys. -s
# records it, and sbctl's hook signs it again on every update. It records no
# file signed already (sbctl 0.18, Sign in sbctl.go), which leaves the boot
# images to sbctl's mkinitcpio hook, which signs each as it is built.
if [ -f "${MNT}${RECOVERY_EFI}" ]; then
    arch-chroot "$MNT" sbctl sign -s "$RECOVERY_EFI" || echo "signing the Recovery failed" >&2
fi

# fwupd's firmware updater, which it starts from the EFI partition, signed under
# the name fwupd prefers. It is loaded without shim, which Arch does not ship,
# so fwupd is told that through its own tool, whose --json leaves out the
# progress it draws and keeps the error.
# https://github.com/fwupd/fwupd/blob/main/plugins/uefi-capsule/README.md
updater=/usr/lib/fwupd/efi/fwupdx64.efi
if [ -f "${MNT}${updater}" ]; then
    arch-chroot "$MNT" sbctl sign -s -o "${updater}.signed" "$updater" || echo "signing fwupd's updater failed" >&2
    arch-chroot "$MNT" fwupdtool --json modify-config uefi_capsule DisableShimForSecureBoot true ||
        echo "fwupd still looks for shim, firmware updates need Secure Boot off" >&2
fi

# Keys are enrolled only in setup mode, read from the UEFI variable: the first
# four bytes are attributes, the fifth the value.
setup_mode=/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c
if [ ! -r "$setup_mode" ] || [ "$(od -An -t u1 -j 4 -N 1 "$setup_mode" 2>/dev/null | tr -d ' ')" != "1" ]; then
    echo "Secure Boot: the firmware is not in setup mode, so no keys were enrolled (the boot chain is signed, so enrolling later is enough)"
    return 0
fi
if arch-chroot "$MNT" sbctl enroll-keys -m; then
    echo "Secure Boot: keys enrolled, switch Secure Boot on in the firmware settings"
else
    echo "Secure Boot: enrolling the keys failed" >&2
fi

# The boot chain signed with this machine's own keys, which the loader task
# made. Never fatal: a machine without Secure Boot boots perfectly well.
# docs/REFERENCE.md#secure-boot
# https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot

# -s records each file, and sbctl's hook signs them again on every update.
# systemd-boot is signed at its source, which systemd-boot-update copies from.
stub=/usr/lib/systemd/boot/efi/systemd-bootx64.efi
arch-chroot "$MNT" sbctl sign -s -o "${stub}.signed" "$stub" || echo "signing systemd-boot failed" >&2
arch-chroot "$MNT" sbctl sign -s "/boot/EFI/Linux/arch-${KERNEL}.efi" || echo "signing the kernel image failed" >&2
arch-chroot "$MNT" sbctl sign -s "/boot/EFI/Linux/arch-${KERNEL}-fallback.efi" || echo "signing the fallback image failed" >&2

# The Recovery starts from the same menu, so it carries the same keys.
if [ -f "${MNT}${RECOVERY_EFI}" ]; then
    arch-chroot "$MNT" sbctl sign -s "$RECOVERY_EFI" || echo "signing the Recovery failed" >&2
fi

# The signed loader over the unsigned one on the EFI partition.
arch-chroot "$MNT" bootctl --esp-path=/boot install || echo "reinstalling the signed systemd-boot failed" >&2

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

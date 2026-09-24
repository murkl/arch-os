# Every part of the boot chain signed with this machine's own keys, which the
# initramfs task made. The last thing that happens to the new system, and never
# fatal - a machine without Secure Boot boots perfectly well.
#
# Why it runs last and why the keys are only enrolled in setup mode:
# docs/REFERENCE.md and https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot

# -s records each file in sbctl's database, and its pacman hook re-signs
# everything in there on each kernel or systemd update.
#
# systemd-boot is signed at its source under /usr/lib, which bootctl prefers.
# Signing the copy on the EFI partition would break at the next systemd update,
# when systemd-boot-update.service copies the new unsigned binary over it.
stub=/usr/lib/systemd/boot/efi/systemd-bootx64.efi
arch-chroot "$MNT" sbctl sign -s -o "${stub}.signed" "$stub" || echo "signing systemd-boot failed"
arch-chroot "$MNT" sbctl sign -s "/boot/EFI/Linux/arch-${KERNEL}.efi" || echo "signing the kernel image failed"
arch-chroot "$MNT" sbctl sign -s "/boot/EFI/Linux/arch-${KERNEL}-fallback.efi" || echo "signing the fallback image failed"

# The Recovery starts from the same menu, so it is signed with the same keys -
# and then starts with Secure Boot on, where the ISO needs it switched off.
if [ -f "${MNT}${RECOVERY_EFI}" ]; then
    arch-chroot "$MNT" sbctl sign -s "$RECOVERY_EFI" || echo "signing the Recovery failed"
fi

# Puts the now signed loader on the EFI partition, over the unsigned one the
# systemd-boot task left there.
arch-chroot "$MNT" bootctl --esp-path=/boot install || echo "reinstalling the signed systemd-boot failed"

# The firmware is in setup mode only while its key hierarchy is empty, which is
# the one state our own keys may be enrolled in - "Secure Boot disabled" is not
# the same thing. Read from the UEFI variable rather than out of `sbctl status`:
# the first four bytes are attributes, the fifth holds the value.
setup_mode=/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c
if [ ! -r "$setup_mode" ] || [ "$(od -An -t u1 -j 4 -N 1 "$setup_mode" 2>/dev/null | tr -d ' ')" != "1" ]; then
    echo "Secure Boot: the firmware is not in setup mode, so no keys were enrolled (the boot chain is signed, so enrolling later is enough)"
    return 0
fi
if arch-chroot "$MNT" sbctl enroll-keys -m; then
    echo "Secure Boot: keys enrolled, switch Secure Boot on in the firmware settings"
else
    echo "Secure Boot: enrolling the keys failed"
fi

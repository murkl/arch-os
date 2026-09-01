# Secure Boot: our own keys, and every part of the boot chain signed with them.
#
# Deliberately the last thing that happens to the new system. The graphics driver
# and the boot splash both rebuild the kernel image directly rather than through
# pacman, so sbctl's own hook never fires for them and would leave a freshly
# rebuilt, unsigned image behind. Signing only holds if nothing rebuilds
# afterwards.
#
# And never fatal. A machine without Secure Boot boots perfectly well, so a
# hiccup here must not throw away an otherwise finished installation. Every
# outcome is in the log, which is copied into the new system afterwards.

simulating && return 0

if ! arch-chroot "$MNT" sbctl create-keys; then
    echo "Secure Boot: creating the keys failed, skipping"
    return 0
fi

# -s records each file in sbctl's database, and its pacman hook re-signs
# everything in there on each kernel or systemd update. That, and nothing else,
# is what keeps this working unattended.
#
# systemd-boot is signed at its source under /usr/lib into an .efi.signed file
# rather than on the EFI partition: bootctl prefers that file when installing or
# updating. Signing the copy on the partition instead would break at the next
# systemd update, when systemd-boot-update.service copies the new unsigned
# binary over it at boot — long after any hook could have signed it.
stub=/usr/lib/systemd/boot/efi/systemd-bootx64.efi
arch-chroot "$MNT" sbctl sign -s -o "${stub}.signed" "$stub" || echo "signing systemd-boot failed"
arch-chroot "$MNT" sbctl sign -s "/boot/EFI/Linux/arch-${ARCH_OS_KERNEL}.efi" || echo "signing the kernel image failed"
arch-chroot "$MNT" sbctl sign -s "/boot/EFI/Linux/arch-${ARCH_OS_KERNEL}-fallback.efi" || echo "signing the fallback image failed"

# Puts the now signed loader on the EFI partition, over the unsigned one the
# boot loader task left there.
arch-chroot "$MNT" bootctl --esp-path=/boot install || echo "reinstalling the signed systemd-boot failed"

# Enrolling replaces the firmware's key hierarchy and is only allowed in setup
# mode. Anything else needs a trip into the UEFI, so it is skipped rather than
# left half done — the setting said so when it was answered.
#
# -m keeps Microsoft's certificates, without which many boards reject their own
# option ROMs and a parallel Windows stops booting.
if ! secure_boot_setup_mode; then
    echo "Secure Boot: the firmware is not in setup mode, so no keys were enrolled — the boot chain is signed, so enrolling later is enough"
    return 0
fi
if arch-chroot "$MNT" sbctl enroll-keys -m; then
    echo "Secure Boot: keys enrolled — switch Secure Boot on in the firmware settings"
else
    echo "Secure Boot: enrolling the keys failed"
fi

# Our own keys, and every part of the boot chain signed with them.
#
# The last thing that happens to the new system, because the graphics driver and
# the boot splash rebuild the kernel image directly rather than through pacman:
# sbctl's hook never fires for them, and signing only holds if nothing rebuilds
# afterwards.
#
# Never fatal. A machine without Secure Boot boots perfectly well, so a hiccup
# here must not throw away a finished installation. Every outcome is in the log.

simulating && return 0

if ! arch-chroot "$MNT" sbctl create-keys; then
    echo "Secure Boot: creating the keys failed, skipping"
    return 0
fi

# -s records each file in sbctl's database, and its pacman hook re-signs
# everything in there on each kernel or systemd update. That is what keeps this
# working unattended.
#
# systemd-boot is signed at its source under /usr/lib, which bootctl prefers when
# installing or updating. Signing the copy on the EFI partition would break at
# the next systemd update, when systemd-boot-update.service copies the new
# unsigned binary over it at boot.
stub=/usr/lib/systemd/boot/efi/systemd-bootx64.efi
arch-chroot "$MNT" sbctl sign -s -o "${stub}.signed" "$stub" || echo "signing systemd-boot failed"
arch-chroot "$MNT" sbctl sign -s "/boot/EFI/Linux/arch-${ARCH_OS_KERNEL}.efi" || echo "signing the kernel image failed"
arch-chroot "$MNT" sbctl sign -s "/boot/EFI/Linux/arch-${ARCH_OS_KERNEL}-fallback.efi" || echo "signing the fallback image failed"

# Puts the now signed loader on the EFI partition, over the unsigned one the
# boot loader task left there.
arch-chroot "$MNT" bootctl --esp-path=/boot install || echo "reinstalling the signed systemd-boot failed"

# Enrolling replaces the firmware's key hierarchy and is only allowed in setup
# mode; anything else needs a trip into the UEFI. -m keeps Microsoft's
# certificates, without which many boards reject their own option ROMs and a
# parallel Windows stops booting.
# The firmware is in setup mode only while its key hierarchy is empty, which is
# the one state our own keys may be enrolled in. "Secure Boot disabled" is not
# the same thing. Read from the UEFI variable rather than out of `sbctl status`:
# the first four bytes are attributes, the fifth holds the value.
setup_mode=/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c
if [ ! -r "$setup_mode" ] || [ "$(od -An -t u1 -j 4 -N 1 "$setup_mode" 2>/dev/null | tr -d ' ')" != "1" ]; then
    echo "Secure Boot: the firmware is not in setup mode, so no keys were enrolled — the boot chain is signed, so enrolling later is enough"
    return 0
fi
if arch-chroot "$MNT" sbctl enroll-keys -m; then
    echo "Secure Boot: keys enrolled — switch Secure Boot on in the firmware settings"
else
    echo "Secure Boot: enrolling the keys failed"
fi

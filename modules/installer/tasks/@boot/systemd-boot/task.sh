# The loader the firmware starts, and how it is told to start this system.
# https://wiki.archlinux.org/title/Systemd-boot

data="$(where)"

# The loader is the new system's own, but the firmware's boot entry is written
# from out here: inside arch-chroot bootctl leaves the EFI variables alone and
# says nothing, and told to write them anyway it cannot see which partition the
# ESP is and writes an entry that points nowhere. Without an entry the firmware
# finds the loader only at \EFI\BOOT\BOOTX64.EFI, after every entry it already
# lists has been tried.
bootctl --root="$MNT" --esp-path=/boot --variables=yes install

# A unified image needs no entry: systemd-boot finds every EFI binary under
# EFI/Linux.
default=main.conf
if secure_boot_wanted; then
    default="arch-${KERNEL}.efi"
fi

render "${data}/loader.conf" DEFAULT="$default" >"${MNT}/boot/loader/loader.conf"

# From module.sh, so these entries and the command line built into a unified
# image cannot disagree about how this system boots.
if ! secure_boot_wanted; then
    cmdline="$(kernel_args)"
    for entry in main main-fallback; do
        render "${data}/${entry}.conf" KERNEL="$KERNEL" CMDLINE="$cmdline" \
            >"${MNT}/boot/loader/entries/${entry}.conf"
    done
fi

arch-chroot "$MNT" systemctl enable systemd-boot-update.service

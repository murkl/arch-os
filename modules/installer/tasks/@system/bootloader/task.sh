# The images the firmware starts and the loader that starts them: a ram disk
# with systemd-boot entries, or, where the chain is signed, a unified kernel
# image found on its own. Why these hooks: docs/REFERENCE.md#the-boot-chain
# https://wiki.archlinux.org/title/Mkinitcpio#Common_hooks
# https://wiki.archlinux.org/title/Systemd-boot

data="$(where)"

# The kernel command line, one answer for the image and the entries alike.
# Why each parameter is here: docs/REFERENCE.md#the-boot-chain
kernel_args() {
    local args=(rw) system_part
    system_part="$(system_partition "$ARCH_OS_DISK")"

    if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
        args+=(root=/dev/mapper/cryptroot "rd.luks.name=$(blkid -s UUID -o value "$system_part")=cryptroot")
    else
        args+=("root=PARTUUID=$(lsblk -dno PARTUUID "$system_part")")
    fi

    args+=(rootflags=subvol=@ rootfstype=btrfs)
    args+=(zswap.enabled=0) # pointless next to zram, and the two interfere

    [ "$ARCH_OS_CORE_TWEAKS_ENABLED" = "true" ] && args+=(nowatchdog)

    # https://wiki.archlinux.org/title/Silent_boot
    if [ "$ARCH_OS_BOOTSPLASH_ENABLED" = "true" ] || [ "$ARCH_OS_CORE_TWEAKS_ENABLED" = "true" ]; then
        args+=(quiet splash vt.global_cursor_default=0 loglevel=3 rd.udev.log_level=3 systemd.show_status=auto)
    fi

    # Plymouth falls back to text for good once it finds a serial console, and
    # a virtual machine is handed one without asking.
    if [ "$ARCH_OS_BOOTSPLASH_ENABLED" = "true" ]; then
        args+=(plymouth.ignore-serial-consoles)
    fi

    [ -n "$ARCH_OS_KERNEL_ARGS" ] && args+=("$ARCH_OS_KERNEL_ARGS")
    printf '%s' "${args[*]}"
}

encrypt_hook=""
[ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && encrypt_hook=" sd-encrypt"
hooks="base systemd keyboard autodetect microcode modconf kms sd-vconsole block${encrypt_hook} filesystems"

# A drop-in, so the boot splash (20-) and the graphics driver (30-) build on it.
mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
render "${data}/10-arch-os.conf" HOOKS="$hooks" >"${MNT}/etc/mkinitcpio.conf.d/10-arch-os.conf"

key=image
if secure_boot_wanted; then
    key=uki
    mkdir -p "${MNT}/boot/EFI/Linux" "${MNT}/etc/kernel"

    # Without it mkinitcpio takes /proc/cmdline, the live image's.
    kernel_args >"${MNT}/etc/kernel/cmdline"

    # Made before any snapshot: one without the keys cannot sign what it
    # rebuilds. From here sbctl's hook signs every image. Never fatal.
    arch-chroot "$MNT" sbctl create-keys || echo "Secure Boot: creating the keys failed, nothing will be signed" >&2
fi

# Written whole on both paths: the template mkinitcpio writes on its own has no
# fallback image, while a boot entry would still point at one.
mapfile -t images < <(boot_images)
render "${data}/${key}.preset" KERNEL="$KERNEL" DEFAULT="${images[0]}" FALLBACK="${images[1]}" \
    >"${MNT}/etc/mkinitcpio.d/${KERNEL}.preset"
arch-chroot "$MNT" mkinitcpio -P

# The plain ram disks the kernel package built, which nothing updates now.
if secure_boot_wanted; then
    rm -f "${MNT}/boot/initramfs-${KERNEL}.img" "${MNT}/boot/initramfs-${KERNEL}-fallback.img"
fi

# The firmware's entry is written from out here: inside arch-chroot bootctl
# cannot see which partition the ESP is and writes one that points nowhere.
bootctl --root="$MNT" --esp-path=/boot --variables=yes install

# A unified image needs no entry: systemd-boot lists EFI/Linux on its own.
default=main.conf
secure_boot_wanted && default="arch-${KERNEL}.efi"
render "${data}/loader.conf" DEFAULT="$default" >"${MNT}/boot/loader/loader.conf"

if ! secure_boot_wanted; then
    cmdline="$(kernel_args)"
    for entry in main main-fallback; do
        render "${data}/${entry}.conf" KERNEL="$KERNEL" CMDLINE="$cmdline" \
            >"${MNT}/boot/loader/entries/${entry}.conf"
    done
fi

arch-chroot "$MNT" systemctl enable systemd-boot-update.service

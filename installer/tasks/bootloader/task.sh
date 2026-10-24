# The images the firmware starts and the loader that starts them. Why these
# hooks and arguments: docs/REFERENCE.md#the-boot-chain
# https://wiki.archlinux.org/title/Mkinitcpio#Common_hooks
# https://wiki.archlinux.org/title/Systemd-boot

data="$(where)"

# The boot without its log, with the splash or without it.
# https://wiki.archlinux.org/title/Silent_boot
silent_boot() { [ "$ARCH_OS_BOOTSPLASH_ENABLED" = "true" ] || [ "$ARCH_OS_CORE_TWEAKS_ENABLED" = "true" ]; }

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
    args+=(panic=10)        # restarts, so the loader counts the start as failed

    [ "$ARCH_OS_CORE_TWEAKS_ENABLED" = "true" ] && args+=(nowatchdog)

    if silent_boot; then
        args+=(quiet splash vt.global_cursor_default=0 loglevel=3 rd.udev.log_level=3 systemd.show_status=auto)
    fi

    # Behind encryption the password comes first: the splash waits for the
    # graphics driver, and up to 3 s, longer than a disk takes, for the question.
    if [ "$ARCH_OS_BOOTSPLASH_ENABLED" = "true" ]; then
        args+=(plymouth.ignore-serial-consoles)
        if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
            args+=(plymouth.use-simpledrm=0 plymouth.splash-delay=3)
        fi
    fi

    [ -n "$ARCH_OS_KERNEL_ARGS" ] && args+=("$ARCH_OS_KERNEL_ARGS")
    printf '%s' "${args[*]}"
}

encrypt_hook=""
[ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && encrypt_hook=" sd-encrypt"
hooks="base systemd keyboard autodetect microcode modconf kms sd-vconsole block${encrypt_hook} filesystems"

# An emergency shell opens for nobody behind the locked root, and waits for a
# key forever. Restarting instead lets the tries run out. Written before the ram
# disk is built, whose systemd hook carries a unit's drop-ins along with it.
mkdir -p "${MNT}/etc/systemd/system/emergency.service.d"
render "${data}/emergency.conf" >"${MNT}/etc/systemd/system/emergency.service.d/10-arch-os.conf"

# A drop-in, so the boot splash (20-) and the graphics driver (30-) build on it.
mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
render "${data}/10-arch-os.conf" HOOKS="$hooks" >"${MNT}/etc/mkinitcpio.conf.d/10-arch-os.conf"

kind="$(boot_kind)"
if [ "$kind" = uki ]; then
    mkdir -p "${MNT}${UKI_DIR}" "${MNT}/etc/kernel"

    # Without it mkinitcpio takes /proc/cmdline, the live image's.
    kernel_args >"${MNT}/etc/kernel/cmdline"

    # Made before any snapshot: one without the keys cannot sign what it
    # rebuilds. From here sbctl's hook signs every image. Never fatal.
    arch-chroot "$MNT" sbctl create-keys || echo "Secure Boot: creating the keys failed, nothing will be signed" >&2

    # systemd-boot signed at its source, which bootctl below and
    # systemd-boot-update copy from. -s records it, so sbctl's hook signs every
    # update of it again.
    stub=/usr/lib/systemd/boot/efi/systemd-bootx64.efi
    arch-chroot "$MNT" sbctl sign -s -o "${stub}.signed" "$stub" || echo "signing systemd-boot failed" >&2
fi

# Written whole on both paths: the template mkinitcpio writes on its own has no
# fallback image, while a boot entry would still point at one.
boot_preset "$MNT" "$kind"
arch-chroot "$MNT" mkinitcpio -P

# The plain ram disks the kernel package built, which nothing updates now.
if [ "$kind" = uki ]; then
    rm -f "${MNT}/boot/initramfs-${KERNEL}.img" "${MNT}/boot/initramfs-${KERNEL}-fallback.img"
fi

# The firmware's entry is written from out here: inside arch-chroot bootctl
# cannot see which partition the ESP is and writes one that points nowhere.
bootctl --root="$MNT" --esp-path=/boot --variables=yes install

# A unified image carries its command line, a ram disk's entry names it.
cmdline=""
[ "$kind" = uki ] || cmdline="$(kernel_args)"
boot_entries "$MNT" "$kind" "$cmdline"

clear_loader_default

arch-chroot "$MNT" systemctl enable systemd-boot-update.service

# The quiet boot hides the cursor on every console, and agetty reads \e as an
# escape: this shows it again before each login.
if silent_boot; then
    mkdir -p "${MNT}/etc/issue.d"
    render "${data}/cursor.issue" >"${MNT}/etc/issue.d/cursor.issue"
fi

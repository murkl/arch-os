# Hooks and kernel arguments: docs/REFERENCE.md#boot-chain
# https://wiki.archlinux.org/title/Mkinitcpio#Common_hooks
# https://wiki.archlinux.org/title/Systemd-boot

data="$(where)"

# https://wiki.archlinux.org/title/Silent_boot
silent_boot() { [ "$ARCH_OS_BOOTSPLASH_ENABLED" = "true" ] || [ "$ARCH_OS_CORE_TWEAKS_ENABLED" = "true" ]; }

# One command line for the UKI and the initramfs entries:
# docs/REFERENCE.md#boot-chain
kernel_args() {
    local args=(rw) system_part
    system_part="$(system_partition "$ARCH_OS_DISK")"

    if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
        args+=(root=/dev/mapper/cryptroot "rd.luks.name=$(blkid -s UUID -o value "$system_part")=cryptroot")
    else
        args+=("root=PARTUUID=$(lsblk -dno PARTUUID "$system_part")")
    fi

    args+=(rootflags=subvol=@ rootfstype=btrfs)
    args+=(zswap.enabled=0) # interferes with zram
    args+=(panic=10)        # reboots, so the loader counts a failed try

    if silent_boot; then
        args+=(quiet splash vt.global_cursor_default=0 loglevel=3 rd.udev.log_level=3 systemd.show_status=auto)
    fi

    # With encryption the passphrase prompt comes first: the splash waits for
    # the GPU driver, and 3 s, longer than the disk takes to appear.
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

# With root locked, the emergency shell waits forever, so it restarts and uses
# up the boot tries. Written before mkinitcpio, whose systemd hook copies it.
mkdir -p "${MNT}/etc/systemd/system/emergency.service.d"
render "${data}/emergency.conf" >"${MNT}/etc/systemd/system/emergency.service.d/10-arch-os.conf"

# 10-, so the bootsplash (20-) and graphics (30-) drop-ins build on it.
mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
render "${data}/10-arch-os.conf" HOOKS="$hooks" >"${MNT}/etc/mkinitcpio.conf.d/10-arch-os.conf"

# A UKI embeds it, otherwise mkinitcpio embeds /proc/cmdline of the live system.
# Beside initramfs entries it is what the Recovery rebuilds them from once they
# are lost.
mkdir -p "${MNT}/etc/kernel"
kernel_args >"${MNT}/etc/kernel/cmdline"

kind="$(boot_kind)"
if [ "$kind" = uki ]; then
    mkdir -p "${MNT}${UKI_DIR}"

    # Before the first snapshot: one without the keys cannot sign what it
    # rebuilds. From here on sbctl's hook signs every image.
    arch-chroot "$MNT" sbctl create-keys || echo "Secure Boot: creating the keys failed, nothing will be signed" >&2

    # Signed at the source bootctl and systemd-boot-update copy from. -s makes
    # sbctl's hook sign every update again.
    stub=/usr/lib/systemd/boot/efi/systemd-bootx64.efi
    arch-chroot "$MNT" sbctl sign -s -o "${stub}.signed" "$stub" || echo "signing systemd-boot failed" >&2
fi

# Written in full: mkinitcpio's own preset has no fallback image, which a boot
# entry points at.
boot_preset "$MNT" "$kind"
restore_kernels "$MNT"
arch-chroot "$MNT" mkinitcpio -P

# The kernel package's plain initramfs images, which nothing updates with UKIs.
if [ "$kind" = uki ]; then
    rm -f "${MNT}/boot/initramfs-${KERNEL}.img" "${MNT}/boot/initramfs-${KERNEL}-fallback.img"
fi

# Outside the chroot: inside it bootctl cannot tell the EFI partition and
# writes a firmware entry that points nowhere.
bootctl --root="$MNT" --esp-path=/boot --variables=yes install

# A UKI embeds the command line, an initramfs entry carries it.
cmdline=""
[ "$kind" = uki ] || cmdline="$(<"${MNT}/etc/kernel/cmdline")"
boot_entries "$MNT" "$kind" "$cmdline"

clear_loader_default

arch-chroot "$MNT" systemctl enable systemd-boot-update.service

# The quiet boot hides the cursor on every console. agetty expands \e, so the
# issue file shows it again before each login.
if silent_boot; then
    mkdir -p "${MNT}/etc/issue.d"
    render "${data}/cursor.issue" >"${MNT}/etc/issue.d/cursor.issue"
    mkdir -p "${MNT}/etc/systemd/system.conf.d"
    render "${data}/watchdog.conf" >"${MNT}/etc/systemd/system.conf.d/10-arch-os.conf"
fi

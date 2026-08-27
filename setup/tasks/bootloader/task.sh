# Install the boot loader and tell it how to start this system.

simulating && return 0

cmdline="$(kernel_args)"

if [ "$ARCH_OS_BOOTLOADER" = "systemd" ]; then

    # This adds an entry to the EFI partition and never overwrites another
    # system's loader — a Windows Boot Manager already there is picked up on its
    # own.
    arch-chroot "$MNT" bootctl --esp-path=/boot install

    # With another system on the disk there has to be a menu to choose it from;
    # on a disk of our own, booting straight through is what people want.
    timeout=0
    [ "$ARCH_OS_DUAL_BOOT_ENABLED" = "true" ] && timeout=5

    # A unified kernel image needs no entry of its own: systemd-boot finds every
    # EFI binary under EFI/Linux and names the entry after the file. Editing the
    # command line is switched off there as well — it sits inside the signed
    # image, and an editable one would hand any bystander a root shell via
    # init=/bin/sh, straight past Secure Boot.
    default=main.conf
    editor=yes
    if secure_boot_wanted; then
        default="arch-${ARCH_OS_KERNEL}.efi"
        editor=no
    fi

    {
        echo "default ${default}"
        echo 'console-mode auto'
        echo "timeout ${timeout}"
        echo "editor ${editor}"
    } >"${MNT}/boot/loader/loader.conf"

    if ! secure_boot_wanted; then
        {
            echo 'title   Arch OS'
            echo "linux   /vmlinuz-${ARCH_OS_KERNEL}"
            echo "initrd  /initramfs-${ARCH_OS_KERNEL}.img"
            echo "options ${cmdline}"
        } >"${MNT}/boot/loader/entries/main.conf"

        {
            echo 'title   Arch OS (fallback)'
            echo "linux   /vmlinuz-${ARCH_OS_KERNEL}"
            echo "initrd  /initramfs-${ARCH_OS_KERNEL}-fallback.img"
            echo "options ${cmdline}"
        } >"${MNT}/boot/loader/entries/main-fallback.conf"
    fi

    arch-chroot "$MNT" systemctl enable systemd-boot-update.service
fi

if [ "$ARCH_OS_BOOTLOADER" = "grub" ]; then

    # Appended inside the existing empty quotes of GRUB_CMDLINE_LINUX. The comma
    # is the substitution delimiter, which is why the answers refuse to contain
    # one.
    sed -i "\,^GRUB_CMDLINE_LINUX=\"\",s,\",&${cmdline}," "${MNT}/etc/default/grub"

    arch-chroot "$MNT" grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

    sed -i "s/^GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=3/" "${MNT}/etc/default/grub"
    sed -i "s/^GRUB_TIMEOUT_STYLE=.*$/GRUB_TIMEOUT_STYLE=menu/" "${MNT}/etc/default/grub"

    # Off by default since GRUB 2.06, and the only way the other system appears
    # in the menu.
    [ "$ARCH_OS_DUAL_BOOT_ENABLED" = "true" ] && echo 'GRUB_DISABLE_OS_PROBER=false' >>"${MNT}/etc/default/grub"

    arch-chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg

    # Rebuilds the menu whenever a snapshot appears or goes.
    [ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && arch-chroot "$MNT" systemctl enable grub-btrfsd.service
fi

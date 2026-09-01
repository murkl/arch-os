# Install the boot loader and tell it how to start this system.

simulating && return 0

cmdline="$(kernel_args)"

if [ "$ARCH_OS_BOOTLOADER" = "systemd" ]; then

    # Adds an entry and never overwrites another system's loader — a Windows
    # Boot Manager already there is picked up on its own.
    arch-chroot "$MNT" bootctl --esp-path=/boot install

    # A menu only where there is another system to choose.
    timeout=0
    [ "$ARCH_OS_DUAL_BOOT_ENABLED" = "true" ] && timeout=5

    # A unified image needs no entry: systemd-boot finds every EFI binary under
    # EFI/Linux. The editor goes off with it — an editable command line hands any
    # bystander a root shell via init=/bin/sh, straight past Secure Boot.
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

    # Appended inside the empty quotes of GRUB_CMDLINE_LINUX. The comma is the
    # substitution delimiter, which is why the answers refuse to contain one.
    #
    # grub-mkconfig reads /etc/default/grub and nothing beside it, so every line
    # below is an edit of a file the grub package owns.
    sed -i "\,^GRUB_CMDLINE_LINUX=\"\",s,\",&${cmdline}," "${MNT}/etc/default/grub"

    arch-chroot "$MNT" grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

    sed -i "s/^GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=3/" "${MNT}/etc/default/grub"
    sed -i "s/^GRUB_TIMEOUT_STYLE=.*$/GRUB_TIMEOUT_STYLE=menu/" "${MNT}/etc/default/grub"

    # Off by default since GRUB 2.06, and the only way the other system appears.
    [ "$ARCH_OS_DUAL_BOOT_ENABLED" = "true" ] && echo 'GRUB_DISABLE_OS_PROBER=false' >>"${MNT}/etc/default/grub"

    arch-chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg

    # Rebuilds the menu whenever a snapshot appears or goes.
    [ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && arch-chroot "$MNT" systemctl enable grub-btrfsd.service
fi

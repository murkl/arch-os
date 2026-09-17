# The loader the firmware starts, and how it is told to start this system. Its
# own task beside the GRUB one, so a run that installs the other never even
# lists this step. https://wiki.archlinux.org/title/Systemd-boot

simulating && return 0

# Adds an entry and never overwrites another system's loader - a Windows Boot
# Manager already there is picked up on its own.
arch-chroot "$MNT" bootctl --esp-path=/boot install

# A menu only where there is another system to choose.
timeout=0
[ "$ARCH_OS_DUAL_BOOT_ENABLED" = "true" ] && timeout=5

# A unified image needs no entry: systemd-boot finds every EFI binary under
# EFI/Linux. The editor goes with it - an editable command line hands any
# bystander a root shell through init=/bin/sh, straight past Secure Boot.
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

# From module.sh, so these entries and the command line built into a unified
# image cannot disagree about how this system boots.
if ! secure_boot_wanted; then
    cmdline="$(kernel_args)"

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

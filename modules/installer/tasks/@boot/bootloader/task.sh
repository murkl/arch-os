# The boot chain: the initial ram disk - or, where the chain is signed, the
# unified kernel image that replaces it - and the loader that starts it.

simulating && return 0

cmdline="$(kernel_args)"

# https://wiki.archlinux.org/title/Mkinitcpio#Common_hooks
btrfs_hook=""
[ "$ARCH_OS_FILESYSTEM" = "btrfs" ] && [ "$ARCH_OS_BOOTLOADER" = "grub" ] && btrfs_hook=" grub-btrfs-overlayfs"

# No kms hook on purpose. With it, the card is handed from the firmware
# framebuffer to the real driver while plymouth is already drawing, and the
# console takes the screen back: no splash, and the passphrase asked in plain
# text. Without it the handover happens after the root file system is mounted.
encrypt_hook=""
[ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && encrypt_hook=" sd-encrypt"

hooks="base systemd keyboard autodetect microcode modconf sd-vconsole block${encrypt_hook} filesystems fsck${btrfs_hook}"

# As a drop-in, not as an edit of /etc/mkinitcpio.conf: that file belongs to the
# mkinitcpio package and editing it would leave a .pacnew to merge every time
# upstream touches it. mkinitcpio reads its own file first and every
# /etc/mkinitcpio.conf.d/*.conf after it, in name order, so what is set here
# wins, and later drop-ins can still build on it (see the boot splash and the
# graphics driver).
mkdir -p "${MNT}/etc/mkinitcpio.conf.d"
{
    echo '# Written by the Arch OS Installer.'
    echo "HOOKS=(${hooks})"
} >"${MNT}/etc/mkinitcpio.conf.d/10-arch-os.conf"

# A unified kernel image packs kernel, ram disk and command line into one EFI
# binary that is signed as a whole. Without it the ram disk sits unsigned on the
# one partition that is never encrypted, and a forged ram disk collects the
# passphrase.
if secure_boot_wanted; then
    # The command line moves into the image, so it has to exist first: without
    # this file mkinitcpio falls back to /proc/cmdline, which inside the chroot
    # is the live image's.
    mkdir -p "${MNT}/etc/kernel"
    kernel_args >"${MNT}/etc/kernel/cmdline"

    # Written whole rather than patched: mkinitcpio creates a preset from a
    # template only when it is missing, so this file is ours and survives every
    # kernel update.
    {
        echo "# Written by the Arch OS Installer: a signed unified kernel image"
        echo "# instead of a bare initramfs, for Secure Boot."
        echo "ALL_kver=\"/boot/vmlinuz-${ARCH_OS_KERNEL}\""
        # Named outright: mkinitcpio's last resort is /proc/cmdline.
        echo "ALL_cmdline=\"/etc/kernel/cmdline\""
        echo "PRESETS=('default' 'fallback')"
        echo "default_uki=\"/boot/EFI/Linux/arch-${ARCH_OS_KERNEL}.efi\""
        echo "fallback_uki=\"/boot/EFI/Linux/arch-${ARCH_OS_KERNEL}-fallback.efi\""
        echo "fallback_options=\"-S autodetect\""
    } >"${MNT}/etc/mkinitcpio.d/${ARCH_OS_KERNEL}.preset"
    mkdir -p "${MNT}/boot/EFI/Linux"
fi

arch-chroot "$MNT" mkinitcpio -P

# Installing the kernel already built a pair of plain ram disks from the preset
# the package ships. With the preset above they are never written again, and an
# initramfs nothing updates is what the unified image is here to do away with.
if secure_boot_wanted; then
    rm -f "${MNT}/boot/initramfs-${ARCH_OS_KERNEL}.img" "${MNT}/boot/initramfs-${ARCH_OS_KERNEL}-fallback.img"
fi

# ----------------------------------------------------------------------------

# The loader itself, and how it is told to start this system.

if [ "$ARCH_OS_BOOTLOADER" = "systemd" ]; then

    # Adds an entry and never overwrites another system's loader - a Windows
    # Boot Manager already there is picked up on its own.
    arch-chroot "$MNT" bootctl --esp-path=/boot install

    # A menu only where there is another system to choose.
    timeout=0
    [ "$ARCH_OS_DUAL_BOOT_ENABLED" = "true" ] && timeout=5

    # A unified image needs no entry: systemd-boot finds every EFI binary under
    # EFI/Linux. The editor is switched off with it too: an editable command
    # line hands any bystander a root shell via init=/bin/sh, straight past
    # Secure Boot.
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

    # Rebuilds the menu whenever a snapshot appears or goes. An if block rather
    # than a guard because it is the last thing this task does: a guard that
    # does not fire leaves 1 behind, and that is what the task hands back.
    if [ "$ARCH_OS_FILESYSTEM" = "btrfs" ]; then
        arch-chroot "$MNT" systemctl enable grub-btrfsd.service
    fi
fi

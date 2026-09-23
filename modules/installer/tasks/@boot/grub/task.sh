# The loader the firmware starts, and how it is told to start this system. Its
# own task beside the systemd-boot one, so a run that installs the other never
# even lists this step. https://wiki.archlinux.org/title/GRUB
#
# grub-mkconfig sources /etc/default/grub and then every drop-in under
# /etc/default/grub.d, so the file the grub package owns stays as it shipped.

data="$(where)"

arch-chroot "$MNT" grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

# What the command line says comes from module.sh.
mkdir -p "${MNT}/etc/default/grub.d"
render "${data}/10-arch-os.cfg" CMDLINE="$(kernel_args)" >"${MNT}/etc/default/grub.d/10-arch-os.cfg"

# Off by default since GRUB 2.06, and the only way the other system appears.
if [ "$ARCH_OS_DUAL_BOOT_ENABLED" = "true" ]; then
    render "${data}/20-os-prober.cfg" >"${MNT}/etc/default/grub.d/20-os-prober.cfg"
fi

arch-chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg

# Rebuilds the menu whenever a snapshot appears or goes. An if block rather than
# a guard, because it is the last thing this task does.
if [ "$ARCH_OS_FILESYSTEM" = "btrfs" ]; then
    arch-chroot "$MNT" systemctl enable grub-btrfsd.service
fi

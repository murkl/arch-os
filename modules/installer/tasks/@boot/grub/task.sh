# The loader the firmware starts, and how it is told to start this system. Its
# own task beside the systemd-boot one, so a run that installs the other never
# even lists this step. https://wiki.archlinux.org/title/GRUB
#
# grub-mkconfig sources /etc/default/grub and then every drop-in under
# /etc/default/grub.d, so the file the grub package owns stays as it shipped.

data="$(where)"

arch-chroot "$MNT" grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB

# What the command line says comes from module.sh, less where root is: GRUB
# writes that into every entry itself. Nothing of the package's own defaults on
# top, so an answer boots the same under either loader. And no microcode image
# in front of the ram disk, which carries it already - see the initramfs task.
mkdir -p "${MNT}/etc/default/grub.d"
render "${data}/10-arch-os.cfg" CMDLINE="$(kernel_options)" >"${MNT}/etc/default/grub.d/10-arch-os.cfg"

arch-chroot "$MNT" grub-mkconfig -o /boot/grub/grub.cfg

# Rebuilds the menu whenever a snapshot appears or goes. An if block rather than
# a guard, because it is the last thing this task does.
if [ "$ARCH_OS_FILESYSTEM" = "btrfs" ]; then
    arch-chroot "$MNT" systemctl enable grub-btrfsd.service
fi

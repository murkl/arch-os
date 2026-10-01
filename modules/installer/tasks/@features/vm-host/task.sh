# The console differs: virt-manager where there is a desktop, virsh where there
# is not. Images land on a subvolume of their own - see docs/REFERENCE.md.
# https://wiki.archlinux.org/title/Libvirt
if [ "$ARCH_OS_DESKTOP" = "none" ]; then
    chroot_pacman_install qemu-base libvirt virt-install dnsmasq edk2-ovmf
else
    chroot_pacman_install qemu-desktop libvirt virt-install virt-manager dnsmasq edk2-ovmf
fi

arch-chroot "$MNT" systemctl enable libvirtd.socket

# Without it every virsh and virt-manager asks for the root password.
arch-chroot "$MNT" usermod -aG libvirt "$ARCH_OS_USERNAME"

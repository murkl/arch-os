# What it takes to run virtual machines on this one: libvirt, a guest firmware
# and dnsmasq either way. What differs is the console: qemu-desktop and
# virt-manager where there is a desktop to open them in, qemu-base and virsh
# where there is not. The disk images land on a subvolume of their own - see
# docs/REFERENCE.md. https://wiki.archlinux.org/title/Libvirt

if [ "$ARCH_OS_DESKTOP" = "none" ]; then
    chroot_pacman_install qemu-base libvirt virt-install dnsmasq edk2-ovmf
else
    chroot_pacman_install qemu-desktop libvirt virt-install virt-manager dnsmasq edk2-ovmf
fi

# The socket rather than the service: the daemon starts with the first command
# that speaks to it.
arch-chroot "$MNT" systemctl enable libvirtd.socket

# Without it every virsh and every virt-manager window asks for a root password.
arch-chroot "$MNT" usermod -aG libvirt "$ARCH_OS_USERNAME"

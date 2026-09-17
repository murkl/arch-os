# Two sides of one switch, and which applies is detected rather than asked.
# Inside a virtual machine this installs the guest tools; on real hardware there
# is no guest to support, so it installs what it takes to run one instead.
# https://wiki.archlinux.org/title/Libvirt

simulating && return 0

case "$(systemd-detect-virt || true)" in

kvm)
    echo "detected KVM"
    # The guest halves alone - the spice server and its GTK client are the
    # host's and drag a desktop's worth of libraries into a guest. Neither unit
    # is switched on here: both are static and started by udev when their virtio
    # port turns up.
    chroot_pacman_install spice-vdagent qemu-guest-agent
    ;;

vmware)
    echo "detected VMware"
    chroot_pacman_install open-vm-tools
    arch-chroot "$MNT" systemctl enable vmtoolsd
    arch-chroot "$MNT" systemctl enable vmware-vmblock-fuse
    ;;

oracle)
    echo "detected VirtualBox"
    chroot_pacman_install virtualbox-guest-utils
    arch-chroot "$MNT" systemctl enable vboxservice
    ;;

microsoft)
    echo "detected Hyper-V"
    chroot_pacman_install hyperv
    # The two units the package ships. File copy lost its daemon when the
    # kernel replaced it with hv_fcopy_uio_daemon, which ships no unit.
    arch-chroot "$MNT" systemctl enable hv_kvp_daemon
    arch-chroot "$MNT" systemctl enable hv_vss_daemon
    ;;

*)
    echo "no virtual machine detected, installing what it takes to run one"

    # libvirt, a guest firmware and dnsmasq either way. What differs is the
    # console: qemu-desktop and virt-manager where there is a desktop to open
    # them in, qemu-base and virsh where there is not.
    if [ "$ARCH_OS_DESKTOP" = "none" ]; then
        chroot_pacman_install qemu-base libvirt virt-install dnsmasq edk2-ovmf
    else
        chroot_pacman_install qemu-desktop libvirt virt-install virt-manager dnsmasq edk2-ovmf
    fi

    # The socket rather than the service: the daemon starts with the first
    # command that speaks to it.
    arch-chroot "$MNT" systemctl enable libvirtd.socket

    # Without it every virsh and every virt-manager window asks for a root
    # password.
    arch-chroot "$MNT" usermod -aG libvirt "$ARCH_OS_USERNAME"
    ;;

esac

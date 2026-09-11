# Two sides of one switch, and which one applies is detected rather than asked
# about. Inside a virtual machine this installs the guest tools, so the screen
# resizes and the clipboard is shared. On real hardware there is no guest to
# support, so what it installs is the other end: what it takes to run a virtual
# machine of your own.
#
# https://wiki.archlinux.org/title/Libvirt
# https://wiki.archlinux.org/title/QEMU

simulating && return 0

case "$(systemd-detect-virt || true)" in

kvm)
    echo "detected KVM"
    # The guest halves alone: spice-vdagent resizes the screen and shares the
    # clipboard, qemu-guest-agent lets the host read and steer this machine. The
    # spice server, its GTK client and the protocol headers are the host's half
    # and drag a desktop's worth of libraries into a guest that has no use for
    # them.
    #
    # Neither is switched on here: both units are static and started by udev
    # when their virtio port turns up, and `systemctl enable` on a static unit
    # is a line that does nothing and says it worked.
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
    # kernel replaced it with hv_fcopy_uio_daemon, which comes with no unit at
    # all, so there is nothing left to switch on for it.
    arch-chroot "$MNT" systemctl enable hv_kvp_daemon
    arch-chroot "$MNT" systemctl enable hv_vss_daemon
    ;;

*)
    echo "no virtual machine detected, installing what it takes to run one"

    # libvirt and a guest firmware either way, and dnsmasq for the network it
    # puts guests on. What differs is the console: qemu-desktop brings the
    # graphical one and virt-manager the window that drives it, neither of
    # which a text console can open. There, virt-install and virsh are the
    # whole interface, and qemu-base is the build with no display backends in
    # it - a desktop's worth of libraries for a machine that has no desktop.
    if [ "$ARCH_OS_DESKTOP" = "none" ]; then
        chroot_pacman_install qemu-base libvirt virt-install dnsmasq edk2-ovmf
    else
        chroot_pacman_install qemu-desktop libvirt virt-install virt-manager dnsmasq edk2-ovmf
    fi

    # The socket rather than the service: the daemon starts with the first
    # command that speaks to it and never runs on a machine that speaks to it
    # never.
    arch-chroot "$MNT" systemctl enable libvirtd.socket

    # Without it every virsh and every virt-manager window asks for a root
    # password. The account is already in wheel and may sudo, so it gains
    # nothing it could not have taken anyway.
    arch-chroot "$MNT" usermod -aG libvirt "$ARCH_OS_USERNAME"
    ;;

esac

# Guest tools, if this is running inside a virtual machine. Detected rather than
# asked about; on real hardware it finds nothing and does nothing.

simulating && return 0

case "$(systemd-detect-virt || true)" in

kvm)
    echo "detected KVM"
    chroot_pacman_install spice spice-vdagent spice-protocol spice-gtk qemu-guest-agent
    arch-chroot "$MNT" systemctl enable qemu-guest-agent
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
    echo "no virtual machine detected"
    ;;
esac

# The guest half of a virtual machine, for whichever hypervisor this one runs
# under. Running virtual machines of its own is the vm-host task.

case "$(systemd-detect-virt || true)" in

kvm | qemu)
    # qemu as well as kvm: the same machine, told apart only by whether the
    # host had hardware virtualisation to hand it. The guest is the same guest.
    echo "detected QEMU"
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

# A hypervisor none of the above knows - Xen, Parallels, a cloud one. There are
# no guest tools here to install for it.
*)
    echo "detected $(systemd-detect-virt || true), which has no guest tools here - nothing installed"
    ;;

esac

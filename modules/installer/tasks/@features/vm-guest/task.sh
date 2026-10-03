# The guest half, for whichever hypervisor this runs under.
case "$(systemd-detect-virt || true)" in

kvm | qemu)
    # The same guest with or without hardware virtualisation. Only the guest
    # halves; both units are static and started by udev.
    echo "detected QEMU"
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
    # File copy lost its daemon to hv_fcopy_uio_daemon, which ships no unit.
    echo "detected Hyper-V"
    chroot_pacman_install hyperv
    arch-chroot "$MNT" systemctl enable hv_kvp_daemon
    arch-chroot "$MNT" systemctl enable hv_vss_daemon
    ;;

*)
    echo "detected $(systemd-detect-virt || true), which has no guest tools here - nothing installed"
    ;;

esac

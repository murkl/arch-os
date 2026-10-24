# The guest half, for whichever hypervisor this runs under.
case "$(systemd-detect-virt || allow 1)" in

kvm | qemu)
    # The same guest with or without hardware virtualization. Only the guest
    # halves, each unit static and started by udev.
    echo "detected QEMU"
    chroot_pacman_install qemu-guest-agent
    # The clipboard and the screen size, which only a desktop has, and the
    # shared folders of GNOME Boxes, announced through avahi, which only a
    # desktop runs.
    if [ "$ARCH_OS_DESKTOP" != "none" ]; then
        chroot_pacman_install spice-vdagent phodav
    fi
    ;;

vmware)
    echo "detected VMware"
    chroot_pacman_install open-vm-tools
    arch-chroot "$MNT" systemctl enable vmtoolsd
    arch-chroot "$MNT" systemctl enable vmware-vmblock-fuse
    ;;

oracle)
    # Without a desktop, the build that leaves out the X11 clipboard and screen.
    echo "detected VirtualBox"
    if [ "$ARCH_OS_DESKTOP" != "none" ]; then
        chroot_pacman_install virtualbox-guest-utils
    else
        chroot_pacman_install virtualbox-guest-utils-nox
    fi
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
    echo "detected $(systemd-detect-virt || allow 1), which has no guest tools here, nothing installed"
    ;;

esac

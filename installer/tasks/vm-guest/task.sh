case "$(systemd-detect-virt || allow 1)" in

kvm | qemu)
    # The same guest with or without hardware virtualization. Its units are
    # static and started by udev.
    echo "detected QEMU"
    chroot_pacman_install qemu-guest-agent
    # Clipboard, screen size and the shared folders of GNOME Boxes, all of which
    # need a desktop.
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
    # Without a desktop, the build without X11.
    echo "detected VirtualBox"
    if [ "$ARCH_OS_DESKTOP" != "none" ]; then
        chroot_pacman_install virtualbox-guest-utils
    else
        chroot_pacman_install virtualbox-guest-utils-nox
    fi
    arch-chroot "$MNT" systemctl enable vboxservice
    # Shared folders mount for the vboxsf group only.
    arch-chroot "$MNT" usermod -aG vboxsf "$ARCH_OS_USERNAME"
    ;;

microsoft)
    # No file copy: hv_fcopy_uio_daemon ships no unit.
    echo "detected Hyper-V"
    chroot_pacman_install hyperv
    arch-chroot "$MNT" systemctl enable hv_kvp_daemon
    arch-chroot "$MNT" systemctl enable hv_vss_daemon
    ;;

*)
    echo "detected $(systemd-detect-virt || allow 1), no guest tools"
    ;;

esac

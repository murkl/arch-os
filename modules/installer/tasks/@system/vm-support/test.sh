# What was installed depends on which side of the switch this machine is on, so
# this asks the same question the task did. In a guest that is the agents
# themselves: their units are static and started by udev, so there is no
# `is-enabled` that says anything about them.
debugging && return 0

case "$(systemd-detect-virt || true)" in
kvm)
    has_command qemu-ga
    has_command spice-vdagent
    ;;
vmware) arch-chroot "$MNT" systemctl is-enabled vmtoolsd >/dev/null ;;
oracle) arch-chroot "$MNT" systemctl is-enabled vboxservice >/dev/null ;;
microsoft) arch-chroot "$MNT" systemctl is-enabled hv_kvp_daemon >/dev/null ;;
*)
    has_command virsh
    arch-chroot "$MNT" systemctl is-enabled libvirtd.socket >/dev/null
    [ "$ARCH_OS_DESKTOP" = "none" ] || has_command virt-manager
    ;;
esac

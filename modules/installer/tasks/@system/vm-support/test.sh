# What was installed depends on which side of the switch this machine is on, so
# this asks the same question the task did.
debugging && return 0

case "$(systemd-detect-virt || true)" in
kvm) arch-chroot "$MNT" systemctl is-enabled qemu-guest-agent >/dev/null ;;
vmware) arch-chroot "$MNT" systemctl is-enabled vmtoolsd >/dev/null ;;
oracle) arch-chroot "$MNT" systemctl is-enabled vboxservice >/dev/null ;;
microsoft) arch-chroot "$MNT" systemctl is-enabled hv_kvp_daemon >/dev/null ;;
*)
    arch-chroot "$MNT" command -v virsh >/dev/null
    arch-chroot "$MNT" systemctl is-enabled libvirtd.socket >/dev/null
    [ "$ARCH_OS_DESKTOP" = "none" ] || arch-chroot "$MNT" command -v virt-manager >/dev/null
    ;;
esac

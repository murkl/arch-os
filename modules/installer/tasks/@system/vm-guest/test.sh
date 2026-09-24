# What was installed depends on the hypervisor, so this asks the same question
# the task did. The units are static, so there is no `is-enabled` that says
# anything about them.

case "$(systemd-detect-virt || true)" in
kvm | qemu)
    has_command qemu-ga
    has_command spice-vdagent
    ;;
vmware) arch-chroot "$MNT" systemctl is-enabled vmtoolsd >/dev/null ;;
oracle) arch-chroot "$MNT" systemctl is-enabled vboxservice >/dev/null ;;
microsoft) arch-chroot "$MNT" systemctl is-enabled hv_kvp_daemon >/dev/null ;;
# A hypervisor the task left alone has nothing to read back.
*) ;;
esac

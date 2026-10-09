case "$(systemd-detect-virt || true)" in
kvm | qemu)
    has_command qemu-ga
    has_command spice-vdagent
    ;;
vmware) arch-chroot "$MNT" systemctl is-enabled vmtoolsd >/dev/null ;;
oracle) arch-chroot "$MNT" systemctl is-enabled vboxservice >/dev/null ;;
microsoft) arch-chroot "$MNT" systemctl is-enabled hv_kvp_daemon >/dev/null ;;
*) ;;
esac

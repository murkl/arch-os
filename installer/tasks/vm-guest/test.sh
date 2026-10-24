case "$(systemd-detect-virt || allow 1)" in
kvm | qemu)
    has_command qemu-ga
    if [ "$ARCH_OS_DESKTOP" != "none" ]; then
        has_command spice-vdagent
        has_command spice-webdavd
    elif has_command spice-vdagent; then
        echo "spice-vdagent and its GTK are installed without a desktop" >&2
        exit 1
    fi
    ;;
vmware) arch-chroot "$MNT" systemctl is-enabled vmtoolsd >/dev/null ;;
oracle)
    arch-chroot "$MNT" systemctl is-enabled vboxservice >/dev/null
    groups="$(arch-chroot "$MNT" id -nG "$ARCH_OS_USERNAME")"
    [[ " ${groups} " == *" vboxsf "* ]]
    ;;
microsoft) arch-chroot "$MNT" systemctl is-enabled hv_kvp_daemon >/dev/null ;;
*) ;;
esac

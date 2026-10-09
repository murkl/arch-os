has_command virsh
arch-chroot "$MNT" systemctl is-enabled libvirtd.socket >/dev/null
[ "$ARCH_OS_DESKTOP" = "none" ] || has_command virt-manager
